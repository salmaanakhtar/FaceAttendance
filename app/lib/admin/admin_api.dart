import 'package:dio/dio.dart';

import '../config.dart';
import '../device/secure_store.dart';

/// Admin (kiosk-side) API client. Sessions are server-side, revocable,
/// and bound to this device.
class AdminApi {
  AdminApi._();
  static final AdminApi instance = AdminApi._();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
  ));

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _admin;

  Map<String, dynamic>? get admin => _admin;
  bool get isLoggedIn => _accessToken != null;

  Future<void> login(String username, String password, {String? deviceId}) async {
    final res = await _dio.post('/api/v1/admin/login', data: {
      'username': username,
      'password': password,
      if (deviceId != null) 'deviceId': deviceId,
    });
    final body = res.data as Map<String, dynamic>;
    _accessToken = body['accessToken'] as String;
    _refreshToken = body['refreshToken'] as String;
    _admin = body['admin'] as Map<String, dynamic>;
    await SecureStore.instance.setAdminRefreshToken(_refreshToken!);
  }

  Future<bool> tryRestoreSession() async {
    final refresh = await SecureStore.instance.getAdminRefreshToken();
    if (refresh == null) return false;
    try {
      final res = await _dio.post('/api/v1/admin/refresh', data: {'refreshToken': refresh});
      _accessToken = (res.data as Map<String, dynamic>)['accessToken'] as String;
      _refreshToken = refresh;
      final me = await _dio.get('/api/v1/admin/me', options: _auth());
      _admin = me.data as Map<String, dynamic>;
      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      if (_refreshToken != null) {
        await _dio.post('/api/v1/admin/logout', data: {'refreshToken': _refreshToken});
      }
    } catch (_) {}
    _accessToken = null;
    _refreshToken = null;
    _admin = null;
    await SecureStore.instance.clearAdminTokens();
  }

  Options _auth() => Options(headers: {'Authorization': 'Bearer $_accessToken'});

  Future<Map<String, dynamic>> get(String path, [Map<String, dynamic>? query]) async {
    final res = await _dio.get(path, queryParameters: query, options: _auth());
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await _dio.post(path, data: body, options: _auth());
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final res = await _dio.patch(path, data: body, options: _auth());
    return res.data as Map<String, dynamic>;
  }
}
