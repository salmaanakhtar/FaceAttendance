import 'package:dio/dio.dart';
import '../config.dart';
import 'secure_store.dart';

export 'package:dio/dio.dart' show DioException, DioExceptionType;

/// Device API client. Handles handshake, token lifecycle, and network
/// failure classification (so the scanner can distinguish offline vs
/// backend failure).
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  bool _provisioned = false;

  bool get provisioned => _provisioned;

  /// Exchange the provisioned device key for a device token.
  Future<void> handshake() async {
    final key = await SecureStore.instance.getDeviceKey();
    if (key == null) throw StateError('not provisioned');
    final res = await _dio.post(
      '/api/v1/device/handshake',
      data: {'deviceKey': key, 'name': 'kiosk'},
    );
    final body = res.data as Map<String, dynamic>;
    await SecureStore.instance.setDeviceToken(body['token'] as String);
    final org = body['org'] as Map<String, dynamic>?;
    if (org != null) {
      await SecureStore.instance.setOrgId(org['id'] as String);
      await SecureStore.instance.setOrgName(org['name'] as String);
    }
    final siteId = body['siteId'];
    if (siteId != null) await SecureStore.instance.setSiteId(siteId as String);
    final deviceId = body['deviceId'];
    if (deviceId != null) await SecureStore.instance.setDeviceId(deviceId as String);
    _provisioned = true;
  }

  Future<Map<String, dynamic>> _authedGet(String path) async {
    final token = await SecureStore.instance.getDeviceToken();
    if (token == null) throw _NoToken();
    final res = await _dio.get(path, options: Options(headers: {'Authorization': 'Bearer $token'}));
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _authedPost(String path, Map<String, dynamic> body) async {
    final token = await SecureStore.instance.getDeviceToken();
    if (token == null) throw _NoToken();
    final res = await _dio.post(path, data: body, options: Options(headers: {'Authorization': 'Bearer $token'}));
    return res.data as Map<String, dynamic>;
  }

  /// Scan ingest. Throws [OfflineException] on connectivity loss,
  /// [ServerException] on backend errors.
  Future<Map<String, dynamic>> ingestScan({
    required String dedupeKey,
    required String employeeId,
    DateTime? deviceTime,
    String? directionHint,
    double? confidence,
    double? livenessScore,
    String? faceHash,
    bool offline = false,
  }) async {
    try {
      return await _authedPost('/api/v1/scans', {
        'dedupeKey': dedupeKey,
        'employeeId': employeeId,
        if (deviceTime != null) 'deviceTime': deviceTime.toUtc().toIso8601String(),
        if (directionHint != null) 'directionHint': directionHint,
        if (confidence != null) 'confidence': confidence,
        if (livenessScore != null) 'livenessScore': livenessScore,
        if (faceHash != null) 'faceHash': faceHash,
        'syncState': offline ? 'offline' : 'live',
      });
    } on DioException catch (e) {
      final type = e.type;
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.connectionError ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.receiveTimeout) {
        throw OfflineException('no connectivity');
      }
      throw ServerException(e.response?.statusCode ?? 0, e.response?.data);
    }
  }

  Future<Map<String, dynamic>> fetchTemplates() => _authedGet('/api/v1/device/templates');
  Future<Map<String, dynamic>> fetchConfig() => _authedGet('/api/v1/device/config');
}

class _NoToken implements Exception {}

class OfflineException implements Exception {
  final String message;
  OfflineException(this.message);
  @override
  String toString() => message;
}

class ServerException implements Exception {
  final int status;
  final dynamic data;
  ServerException(this.status, this.data);
  @override
  String toString() => 'server error $status: $data';
}
