import { Plus } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { fmtDate, isoDate } from '../lib/format';
import type { Employee, Leave } from '../lib/types';
import { Badge, Button, Card, Empty, Input, Modal, PageHeader, Select, Spinner, TableWrap, Textarea } from '../components/ui';

export function LeavePage() {
  const [rows, setRows] = useState<Leave[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [filter, setFilter] = useState('all');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Leave | null | undefined>(undefined);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [leave, employeeData] = await Promise.all([
        api.request<{ leave: Leave[] }>('/api/v1/admin/leave'),
        api.request<{ employees: Employee[] }>('/api/v1/admin/employees?status=all&limit=200&offset=0'),
      ]);
      setRows(leave.leave ?? []);
      setEmployees(employeeData.employees ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load leave');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const visible = filter === 'all' ? rows : rows.filter((row) => row.status === filter);

  return (
    <div className="space-y-5">
      <PageHeader title="Leave" actions={<Button onClick={() => setEditing(null)}><Plus className="h-4 w-4" /> Record leave</Button>} />
      <Card className="overflow-hidden">
        <div className="flex items-center justify-between gap-2 border-b border-line px-4 py-3">
          <Select value={filter} onChange={(event) => setFilter(event.target.value)} className="h-9 w-40">
            <option value="all">All statuses</option>
            <option value="approved">Approved</option>
            <option value="pending">Pending</option>
            <option value="rejected">Rejected</option>
            <option value="cancelled">Cancelled</option>
          </Select>
          <Badge>{visible.length} records</Badge>
        </div>
        {loading ? <div className="flex justify-center py-16"><Spinner /></div> : error ? <Empty>{error}</Empty> : visible.length ? (
          <TableWrap>
            <table className="w-full min-w-[760px]">
              <thead><tr><th className="th">Worker</th><th className="th">Type</th><th className="th">Dates</th><th className="th">Note</th><th className="th">Status</th><th className="th" /></tr></thead>
              <tbody>
                {visible.map((row) => (
                  <tr key={row.id}>
                    <td className="td">{row.employeeName}</td>
                    <td className="td capitalize">{row.leaveType}</td>
                    <td className="td">{row.startDate === row.endDate ? fmtDate(row.startDate) : `${fmtDate(row.startDate)} – ${fmtDate(row.endDate)}`}</td>
                    <td className="td max-w-[240px] truncate">{row.note || '—'}</td>
                    <td className="td"><Badge tone={row.status === 'approved' ? 'green' : row.status === 'pending' ? 'amber' : row.status === 'rejected' ? 'red' : 'neutral'}>{row.status}</Badge></td>
                    <td className="td text-right"><Button size="sm" variant="secondary" onClick={() => setEditing(row)}>Edit</Button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No matching leave records.</Empty>}
      </Card>

      {editing !== undefined ? (
        <LeaveModal
          entry={editing}
          employees={employees}
          onClose={() => setEditing(undefined)}
          onSaved={async () => { setEditing(undefined); await load(); }}
        />
      ) : null}
    </div>
  );
}

function LeaveModal({
  entry, employees, onClose, onSaved,
}: {
  entry: Leave | null;
  employees: Employee[];
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [employeeId, setEmployeeId] = useState(entry?.employeeId ?? employees.find((employee) => employee.status === 'active')?.id ?? '');
  const [type, setType] = useState(entry?.leaveType ?? 'annual');
  const [status, setStatus] = useState(entry?.status ?? 'approved');
  const [start, setStart] = useState(entry?.startDate ?? isoDate());
  const [end, setEnd] = useState(entry?.endDate ?? isoDate());
  const [note, setNote] = useState(entry?.note ?? '');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    if (end < start) {
      setError('End date must be on or after the start date.');
      return;
    }
    setPending(true);
    setError(null);
    try {
      const body = { startDate: start, endDate: end, leaveType: type, status, note: note.trim(), ...(entry ? {} : { employeeId }) };
      await api.request(entry ? `/api/v1/admin/leave/${entry.id}` : '/api/v1/admin/leave', {
        method: entry ? 'PATCH' : 'POST',
        body,
      });
      await onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save leave');
    } finally {
      setPending(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={entry ? 'Edit leave' : 'Record leave'} footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button type="submit" form="leave-form" disabled={pending}>{pending ? 'Saving…' : 'Save leave'}</Button></>}>
      <form id="leave-form" className="grid gap-4 sm:grid-cols-2" onSubmit={save}>
        <Select label="Worker" value={employeeId} onChange={(event) => setEmployeeId(event.target.value)} disabled={Boolean(entry)} className="sm:col-span-2">
          {employees.filter((employee) => employee.status === 'active' || employee.id === entry?.employeeId).map((employee) => <option key={employee.id} value={employee.id}>{employee.name}</option>)}
        </Select>
        <Select label="Leave type" value={type} onChange={(event) => setType(event.target.value)}>
          <option value="annual">Annual</option>
          <option value="sick">Sick</option>
          <option value="unpaid">Unpaid</option>
          <option value="other">Other</option>
        </Select>
        <Select label="Status" value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="approved">Approved</option>
          <option value="pending">Pending</option>
          <option value="rejected">Rejected</option>
          <option value="cancelled">Cancelled</option>
        </Select>
        <Input label="Start date" type="date" value={start} onChange={(event) => setStart(event.target.value)} required />
        <Input label="End date" type="date" value={end} onChange={(event) => setEnd(event.target.value)} required />
        <Textarea label="Note" value={note} onChange={(event) => setNote(event.target.value)} className="sm:col-span-2" />
        {error ? <p className="sm:col-span-2 rounded-xl border border-danger/20 bg-danger-soft px-3 py-2 text-[11px] text-danger">{error}</p> : null}
      </form>
    </Modal>
  );
}
