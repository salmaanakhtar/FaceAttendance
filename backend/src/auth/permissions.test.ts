import { describe, expect, it } from 'vitest';
import { roleAllows, operationalSchedule } from './permissions.js';

describe('role permissions', () => {
  it('preserves full access for existing administrators and owners', () => {
    for (const role of ['admin', 'owner']) {
      expect(roleAllows(role, 'POST', '/api/v1/admin/payroll/report')).toBe(true);
      expect(roleAllows(role, 'PATCH', '/api/v1/admin/team/id')).toBe(true);
    }
  });
  it('allows supervisors to correct attendance but denies pay, worker and team changes', () => {
    expect(roleAllows('supervisor', 'POST', '/api/v1/admin/corrections')).toBe(true);
    expect(roleAllows('supervisor', 'PATCH', '/api/v1/admin/leave/id')).toBe(true);
    for (const route of ['payroll/report', 'team', 'employees', 'audit', 'export']) {
      expect(roleAllows('supervisor', 'POST', `/api/v1/admin/${route}`)).toBe(false);
    }
  });
  it('viewers can read operational records but cannot mutate or export', () => {
    expect(roleAllows('viewer', 'GET', '/api/v1/admin/attendance?from=2026-11-01')).toBe(true);
    expect(roleAllows('viewer', 'GET', '/api/v1/admin/employees/id')).toBe(true);
    expect(roleAllows('viewer', 'POST', '/api/v1/admin/attendance/id/approve')).toBe(false);
    expect(roleAllows('viewer', 'GET', '/api/v1/admin/payroll/payslips')).toBe(false);
    expect(roleAllows('viewer', 'GET', '/api/v1/admin/audit')).toBe(false);
    expect(roleAllows('unknown', 'GET', '/api/v1/admin/attendance')).toBe(false);
    expect(roleAllows('viewer', 'GET', '/api/v1/admin/attendance-malicious')).toBe(false);
  });
  it('limited profiles exclude pay and identity fields', () => {
    const schedule = { hourlyRate: 40, identityNumber: 'secret', department: 'Sales', workDays: ['mon'] };
    expect(operationalSchedule(schedule)).toEqual({ department: 'Sales', workDays: ['mon'] });
    expect(schedule.hourlyRate).toBe(40);
  });
});
