/** Default-deny policy, evaluated against the current database role on every request. */
export function roleAllows(role: string, method: string, path: string): boolean {
  if (role === 'owner' || role === 'admin') return true;
  if (role !== 'supervisor' && role !== 'viewer') return false;
  const route = path.split('?')[0] ?? '';
  if (route === '/api/v1/admin/me' || route === '/api/v1/admin/logout') return true;
  const attendance = /^\/api\/v1\/admin\/(attendance|corrections|leave)(\/|$)/.test(route);
  const employees = /^\/api\/v1\/admin\/employees(\/|$)/.test(route);
  if (method === 'GET' || method === 'HEAD') return attendance || employees;
  return role === 'supervisor' && ['POST', 'PATCH'].includes(method) && attendance;
}

export function operationalSchedule(schedule: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(schedule).filter(([key]) =>
    ['department', 'hoursPerWeek', 'workDays', 'startTime', 'endTime', 'breakMinutes', 'graceMinutes'].includes(key)));
}
