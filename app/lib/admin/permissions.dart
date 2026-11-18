bool roleCanManage(String role) => role == 'owner' || role == 'admin';
bool roleCanEditAttendance(String role) =>
    roleCanManage(role) || role == 'supervisor';

bool roleAllowsRequest(String role, String method, String path) {
  if (roleCanManage(role)) return true;
  if (role != 'supervisor' && role != 'viewer') return false;
  if (path == '/api/v1/admin/me' || path == '/api/v1/admin/logout') return true;
  final attendance =
      RegExp(r'^/api/v1/admin/(attendance|corrections|leave)(/|$)')
          .hasMatch(path);
  final employees = RegExp(r'^/api/v1/admin/employees(/|$)').hasMatch(path);
  if (method == 'GET') return attendance || employees;
  return role == 'supervisor' &&
      (method == 'POST' || method == 'PATCH') &&
      attendance;
}
