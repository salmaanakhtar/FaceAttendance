import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { hours } from '../lib/format';
import type { OvertimeReport } from '../lib/types';
import { Badge, Button, Card, Empty, Input, PageHeader, Spinner, TableWrap } from '../components/ui';

export function Overtime() {
  const [report, setReport] = useState<OvertimeReport | null>(null);
  const [weekly, setWeekly] = useState('46');
  const [monthly, setMonthly] = useState('184');
  const [enabled, setEnabled] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await api.request<OvertimeReport>('/api/v1/admin/overtime');
      setReport(data);
      setWeekly(String(data.settings.weeklyHours));
      setMonthly(String(data.settings.monthlyHours));
      setEnabled(data.settings.enabled);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load overtime');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function saveSettings(event: React.FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await api.request('/api/v1/admin/overtime/settings', {
        method: 'PUT',
        body: { enabled, weeklyHours: Number(weekly), monthlyHours: Number(monthly) },
      });
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save limits');
    } finally {
      setSaving(false);
    }
  }

  async function apply(employeeId: string, suggested: number) {
    await api.request(`/api/v1/admin/overtime/${employeeId}/apply-suggestion`, {
      method: 'POST',
      body: { weeklyHours: suggested },
    });
    await load();
  }

  if (loading) return <div className="flex justify-center py-20"><Spinner /></div>;

  return (
    <div className="space-y-5">
      <PageHeader title="Overtime" actions={<Button variant="secondary" onClick={() => void load()}>Refresh</Button>} />
      {error ? <Card className="p-4 text-[12px] text-danger">{error}</Card> : null}

      <Card className="overflow-hidden">
        <form className="border-b border-line px-4 py-4" onSubmit={saveSettings}>
          <div className="flex flex-wrap items-end gap-3">
            <Input label="Weekly limit (hours)" type="number" min="1" max="168" step="0.5" value={weekly} onChange={(event) => setWeekly(event.target.value)} className="h-9 w-40" />
            <Input label="Monthly limit (hours)" type="number" min="1" max="744" step="0.5" value={monthly} onChange={(event) => setMonthly(event.target.value)} className="h-9 w-40" />
            <label className="flex h-9 items-center gap-2 text-[12px] text-ink">
              <input type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} />
              Alerts enabled
            </label>
            <Button type="submit" disabled={saving}>{saving ? 'Saving…' : 'Save limits'}</Button>
          </div>
        </form>

        <div className="px-4 py-4">
          <h2 className="text-[14px] font-bold text-ink">Alerts</h2>
          <p className="text-[11px] text-muted">{report?.alerts.length ?? 0} worker(s) over or projected over a limit</p>
        </div>
        {report?.alerts.length ? (
          <TableWrap>
            <table className="w-full min-w-[900px]">
              <thead><tr><th className="th">Worker</th><th className="th">Week</th><th className="th">Month</th><th className="th">Status</th><th className="th">Suggested</th><th className="th" /></tr></thead>
              <tbody>
                {report.alerts.map((alert) => (
                  <tr key={alert.employeeId}>
                    <td className="td"><strong>{alert.employeeName}</strong><br /><span className="text-[10px] text-muted">#{alert.employeeCode}</span></td>
                    <td className="td">{hours(alert.weekly.workedMinutes)} / {hours(alert.weekly.projectedMinutes)}<br /><span className="text-[10px] text-muted">limit {alert.weekly.thresholdMinutes / 60}h</span></td>
                    <td className="td">{hours(alert.monthly.workedMinutes)} / {hours(alert.monthly.projectedMinutes)}<br /><span className="text-[10px] text-muted">limit {alert.monthly.thresholdMinutes / 60}h</span></td>
                    <td className="td"><Badge tone={alert.status === 'exceeded' ? 'red' : 'amber'}>{alert.status === 'exceeded' ? 'Over limit' : 'Projected'}</Badge></td>
                    <td className="td">{alert.suggestedWeeklyHours}h/week<br /><span className="text-[10px] text-muted">{alert.suggestedPerDayHours}h/day</span></td>
                    <td className="td text-right"><Button size="sm" variant="secondary" onClick={() => void apply(alert.employeeId, alert.suggestedWeeklyHours)}>Apply</Button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No overtime alerts.</Empty>}
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b border-line px-4 py-3">
          <h2 className="text-[14px] font-bold text-ink">All workers</h2>
          <p className="text-[11px] text-muted">{report ? `Week ${report.weekStart} to ${report.weekEnd} · month ${report.monthStart} to ${report.monthEnd}` : ''}</p>
        </div>
        {report?.workers.length ? (
          <TableWrap>
            <table className="w-full min-w-[760px]">
              <thead><tr><th className="th">Worker</th><th className="th">Weekly</th><th className="th">Monthly</th><th className="th">Status</th></tr></thead>
              <tbody>
                {report.workers.map((worker) => (
                  <tr key={worker.employeeId}>
                    <td className="td">{worker.employeeName} <span className="text-muted">#{worker.employeeCode}</span></td>
                    <td className="td">{hours(worker.weekly.workedMinutes)} / {hours(worker.weekly.projectedMinutes)} projected</td>
                    <td className="td">{hours(worker.monthly.workedMinutes)} / {hours(worker.monthly.projectedMinutes)} projected</td>
                    <td className="td"><Badge tone={worker.status === 'exceeded' ? 'red' : worker.status === 'projected' ? 'amber' : 'green'}>{worker.status}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No active workers.</Empty>}
      </Card>
    </div>
  );
}
