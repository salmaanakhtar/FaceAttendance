import { Download } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { hours, isoDate, money, monthRange } from '../lib/format';
import type { PayrollReport } from '../lib/types';
import { Badge, Button, Card, Empty, Input, PageHeader, Spinner, TableWrap } from '../components/ui';

export function Payroll() {
  const [month, setMonth] = useState(isoDate().slice(0, 7));
  const [report, setReport] = useState<PayrollReport | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const range = monthRange(month);
      const data = await api.request<PayrollReport>('/api/v1/admin/payroll/report', {
        method: 'POST',
        body: { ...range, format: 'json', adjustments: [] },
      });
      setReport(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load payroll');
    } finally {
      setLoading(false);
    }
  }, [month]);

  useEffect(() => { void load(); }, [load]);

  async function exportExcel() {
    const range = monthRange(month);
    await api.download(
      '/api/v1/admin/payroll/report',
      { ...range, format: 'xlsx', adjustments: [] },
      `payroll-${range.from}-${range.to}.xlsx`,
    );
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title="Payroll"
        actions={<Button onClick={() => void exportExcel()}><Download className="h-4 w-4" /> Download Excel</Button>}
      />
      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-end gap-3 border-b border-line px-4 py-3">
          <Input label="Month" type="month" value={month} onChange={(event) => setMonth(event.target.value)} className="h-9 w-44" />
          <Button variant="secondary" onClick={() => void load()}>Preview</Button>
          <span className="ml-auto text-[11px] text-muted">UIF is calculated at 1% of gross wages.</span>
        </div>
        {loading ? <div className="flex justify-center py-16"><Spinner /></div> : error ? <Empty>{error}</Empty> : report?.workers?.length ? (
          <TableWrap>
            <table className="w-full min-w-[900px]">
              <thead><tr><th className="th">Worker</th><th className="th">Hours</th><th className="th">Rate</th><th className="th">Gross</th><th className="th">UIF (1%)</th><th className="th">Deductions</th><th className="th">Net pay</th><th className="th">Status</th></tr></thead>
              <tbody>
                {report.workers.map((worker) => (
                  <tr key={worker.id}>
                    <td className="td"><strong>{worker.name}</strong> <span className="text-muted">#{worker.code}</span></td>
                    <td className="td">{hours(worker.workedMinutes)}</td>
                    <td className="td">{money(worker.rate)}</td>
                    <td className="td">{money(worker.gross)}</td>
                    <td className="td">{money(worker.uif)}</td>
                    <td className="td">{money(worker.otherDeductions)}</td>
                    <td className="td font-semibold">{money(worker.net)}</td>
                    <td className="td">{worker.unresolvedShifts ? <Badge tone="red">{worker.unresolvedShifts} unfinished</Badge> : <Badge tone="green">Ready</Badge>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No workers for this payroll period.</Empty>}
      </Card>
    </div>
  );
}
