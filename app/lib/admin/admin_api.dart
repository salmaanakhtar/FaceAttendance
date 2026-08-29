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

  Future<List<dynamic>> getList(String path, [Map<String, dynamic>? query]) async {
    final res = await _dio.get(path, queryParameters: query, options: _auth());
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await _dio.post(path, data: body, options: _auth());
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final res = await _dio.patch(path, data: body, options: _auth());
    return res.data as Map<String, dynamic>;
  }

  /// Raw text responses (CSV export).
  Future<String> getText(String path, [Map<String, dynamic>? query]) async {
    final res = await _dio.get(path, queryParameters: query, options: _auth());
    return res.data as String;
  }

  // ---- Employees ----

  Future<Map<String, dynamic>> listEmployees({
    String? search,
    String? status,
    String? enrolled,
    int limit = 100,
    int offset = 0,
  }) =>
      get('/api/v1/admin/employees', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null) 'status': status,
        if (enrolled != null) 'enrolled': enrolled,
        'limit': '$limit',
        'offset': '$offset',
      });

  Future<Map<String, dynamic>> getEmployee(String id) => get('/api/v1/admin/employees/$id');

  Future<Map<String, dynamic>> createEmployee({
    required String name,
    String? employeeCode,
    String? email,
    Map<String, dynamic>? schedule,
  }) =>
      post('/api/v1/admin/employees', {
        'name': name,
        if (employeeCode != null && employeeCode.isNotEmpty) 'employeeCode': employeeCode,
        if (email != null && email.isNotEmpty) 'email': email,
        if (schedule != null) 'schedule': schedule,
      });

  Future<Map<String, dynamic>> updateEmployee(
    String id, {
    String? name,
    String? email,
    Map<String, dynamic>? schedule,
  }) =>
      patch('/api/v1/admin/employees/$id', {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (schedule != null) 'schedule': schedule,
      });

  Future<Map<String, dynamic>> deactivateEmployee(String id) =>
      post('/api/v1/admin/employees/$id/deactivate', {});

  Future<Map<String, dynamic>> deleteEmployee(String id) =>
      post('/api/v1/admin/employees/$id/delete', {});

  Future<Map<String, dynamic>> enrollEmployee(
    String id, {
    required List<double> embedding,
    Map<String, dynamic>? quality,
  }) =>
      post('/api/v1/admin/employees/$id/enroll', {
        'embedding': embedding,
        'templateVersion': kTemplateVersion,
        'quality': quality ?? {},
      });

  // ---- Attendance ----

  Future<Map<String, dynamic>> attendanceNow() => get('/api/v1/admin/attendance/now');

  Future<Map<String, dynamic>> attendanceExceptions({String? from, String? to, int limit = 50}) =>
      get('/api/v1/admin/attendance/exceptions', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> attendanceList({
    String? from,
    String? to,
    String? employeeId,
    String? status,
    int limit = 200,
  }) =>
      get('/api/v1/admin/attendance', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (employeeId != null) 'employeeId': employeeId,
        if (status != null) 'status': status,
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> attendanceEmployee(String id, {String? from, String? to}) =>
      get('/api/v1/admin/attendance/employee/$id', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      });

  Future<Map<String, dynamic>> attendanceStats({String? from, String? to}) =>
      get('/api/v1/admin/attendance/stats', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      });

  Future<Map<String, dynamic>> applyCorrection({
    required String employeeId,
    String? sessionId,
    required String field,
    required String reason,
    String? value,
  }) =>
      post('/api/v1/admin/corrections', {
        'employeeId': employeeId,
        if (sessionId != null) 'sessionId': sessionId,
        'field': field,
        if (value != null) 'value': value,
        'reason': reason,
      });

  Future<Map<String, dynamic>> corrections({String? employeeId, String? sessionId, int limit = 100}) =>
      get('/api/v1/admin/corrections', {
        if (employeeId != null) 'employeeId': employeeId,
        if (sessionId != null) 'sessionId': sessionId,
        'limit': '$limit',
      });

  Future<Map<String, dynamic>> auditLog({int limit = 200}) => get('/api/v1/admin/audit', {'limit': '$limit'});

  Future<String> exportCsv({String? from, String? to}) =>
      getText('/api/v1/admin/export', {if (from != null) 'from': from, if (to != null) 'to': to});
}
