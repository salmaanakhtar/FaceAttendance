import { Activity, AlertTriangle, Clock3, Users } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { fmtTime, hours, isoDate, mondayOf } from '../lib/format';
import type { Employee, OvertimeReport, Session } from '../lib/types';
import {
  Badge,
  Button,
  Card,
  Empty,
  PageHeader,
  Spinner,
  StatCard,
  TableWrap,
} from '../components/ui';

type DashboardData = {
  now: { currentlyIn: Session[] };
  stats: { aggregate?: Record<string, number> };
  employees: { employees: Employee[] };
  day: { sessions: Session[] };
  week: { sessions: Session[] };
  month: { sessions: Session[] };
  overtime: OvertimeReport | null;
};

export function Dashboard() {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const today = isoDate();
    const weekStart = mondayOf(today);
    const monthStart = `${today.slice(0, 7)}-01`;
    try {
      const [now, stats, employees, day, week, month, overtime] = await Promise.all([
        api.request<{ currentlyIn: Session[] }>('/api/v1/admin/attendance/now'),
        api.request<{ aggregate?: Record<string, number> }>(
          `/api/v1/admin/attendance/stats?from=${today}&to=${today}`,
        ),
        api.request<{ employees: Employee[] }>('/api/v1/admin/employees?status=active&limit=200&offset=0'),
        api.request<{ sessions: Session[] }>(`/api/v1/admin/attendance?from=${today}&to=${today}&limit=500`),
        api.request<{ sessions: Session[] }>(`/api/v1/admin/attendance?from=${weekStart}&to=${today}&limit=500`),
        api.request<{ sessions: Session[] }>(`/api/v1/admin/attendance?from=${monthStart}&to=${today}&limit=500`),
        api.request<OvertimeReport>('/api/v1/admin/overtime').catch(() => null),
      ]);
      setData({ now, stats, employees, day, week, month, overtime });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load the dashboard');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <div className="flex justify-center py-20"><Spinner /></div>;
  if (error || !data) {
    return (
      <Card className="p-6 text-center">
        <p className="text-[12px] text-danger">{error}</p>
        <Button className="mt-4" onClick={() => void load()}>Retry</Button>
      </Card>
    );
  }

  const current = data.now.currentlyIn ?? [];
  const employees = data.employees.employees ?? [];
  const agg = data.stats.aggregate ?? {};
  const day = data.day.sessions ?? [];
  const week = data.week.sessions ?? [];
  const month = data.month.sessions ?? [];
  const alerts = data.overtime?.alerts ?? [];
  const total = (employeeId: string, rows: Session[]) =>
    rows.filter((row) => row.employeeId === employeeId).reduce((sum, row) => sum + Number(row.workedMinutes ?? 0), 0);

  return (
    <div className="space-y-5">
      <PageHeader title="Overview" actions={<Button variant="secondary" onClick={() => void load()}>Refresh</Button>} />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard label="Workers currently in" value={current.length} tone="green" icon={<Users className="h-4 w-4" />} />
        <StatCard label="Today's sessions" value={agg.sessions ?? day.length} tone="blue" icon={<Clock3 className="h-4 w-4" />} />
        <StatCard label="Late today" value={agg.lateCount ?? 0} tone="amber" icon={<AlertTriangle className="h-4 w-4" />} />
        <StatCard label="Incomplete" value={agg.incompleteCount ?? 0} tone="red" icon={<Activity className="h-4 w-4" />} />
      </div>

      {alerts.length ? (
        <Card className="overflow-hidden">
          <div className="flex items-center justify-between border-b border-line px-4 py-3">
            <div>
              <h2 className="text-[14px] font-bold text-ink">Overtime alerts</h2>
              <p className="text-[11px] text-muted">{alerts.length} worker(s) projected over a limit</p>
            </div>
            <Link to="/overtime" className="text-[11px] font-semibold text-primary">Open overtime</Link>
          </div>
          <TableWrap>
            <table className="w-full min-w-[780px]">
              <thead><tr><th className="th">Worker</th><th className="th">Week</th><th className="th">Month</th><th className="th">Suggested</th></tr></thead>
              <tbody>
                {alerts.map((alert) => (
                  <tr key={alert.employeeId}>
                    <td className="td"><strong>{alert.employeeName}</strong><br /><span className="text-[10px] text-muted">#{alert.employeeCode}</span></td>
                    <td className="td">{hours(alert.weekly.workedMinutes)} / {hours(alert.weekly.projectedMinutes)} <span className="text-muted">of {alert.weekly.thresholdMinutes / 60}h</span></td>
                    <td className="td">{hours(alert.monthly.workedMinutes)} / {hours(alert.monthly.projectedMinutes)} <span className="text-muted">of {alert.monthly.thresholdMinutes / 60}h</span></td>
                    <td className="td">{alert.suggestedWeeklyHours}h/week <span className="text-muted">({alert.suggestedPerDayHours}h/day)</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        </Card>
      ) : null}

      <Card className="overflow-hidden">
        <div className="flex items-center justify-between border-b border-line px-4 py-3">
          <h2 className="text-[14px] font-bold text-ink">Worker hours</h2>
          <Badge>{employees.length} active</Badge>
        </div>
        <TableWrap>
          <table className="w-full min-w-[760px]">
            <thead><tr><th className="th">Worker</th><th className="th">Status</th><th className="th">Today</th><th className="th">This week</th><th className="th">This month</th></tr></thead>
            <tbody>
              {employees.map((employee) => {
                const open = current.some((row) => row.employeeId === employee.id);
                return (
                  <tr key={employee.id}>
                    <td className="td"><strong>{employee.name}</strong><br /><span className="text-[10px] text-muted">#{employee.employeeCode}</span></td>
                    <td className="td"><Badge tone={open ? 'green' : 'neutral'}>{open ? 'Clocked in' : 'Clocked out'}</Badge></td>
                    <td className="td">{hours(total(employee.id, day))}</td>
                    <td className="td font-semibold text-primary">{hours(total(employee.id, week))}</td>
                    <td className="td font-semibold text-emerald-700">{hours(total(employee.id, month))}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </TableWrap>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-[14px] font-bold text-ink">In right now</h2>
            <Badge tone="green">{current.length}</Badge>
          </div>
          {current.length ? (
            <div className="mt-3 space-y-2">
              {current.map((session) => (
                <div key={session.id} className="flex items-center justify-between rounded-xl bg-canvas px-3 py-2">
                  <span className="text-[12px] font-medium text-ink">{session.employeeName}</span>
                  <span className="text-[10px] text-muted">{fmtTime(session.checkInAt)}</span>
                </div>
              ))}
            </div>
          ) : <Empty>No workers are currently clocked in.</Empty>}
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-[14px] font-bold text-ink">Today</h2>
            <Badge>{day.length} sessions</Badge>
          </div>
          {day.length ? (
            <div className="mt-3 space-y-2">
              {day.slice(0, 8).map((session) => (
                <div key={session.id} className="flex items-center justify-between rounded-xl bg-canvas px-3 py-2">
                  <span className="truncate text-[12px] text-ink">{session.employeeName}</span>
                  <span className="text-[10px] text-muted">{fmtTime(session.checkInAt)}</span>
                </div>
              ))}
            </div>
          ) : <Empty>No attendance recorded today.</Empty>}
        </Card>
      </div>
    </div>
  );
}
