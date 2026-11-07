import { Download, Pencil, Plus, Search } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { fmtTime, hours, isoDate, localInput, monthRange, zonedToUtc } from '../lib/format';
import type { Employee, Session } from '../lib/types';
import {
  Badge, Button, Card, Empty, Input, Modal, PageHeader, Select, Spinner, TableWrap, Textarea,
} from '../components/ui';

export function Attendance() {
  const initial = monthRange();
  const [from, setFrom] = useState(initial.from);
  const [to, setTo] = useState(initial.to);
  const [employeeId, setEmployeeId] = useState('');
  const [status, setStatus] = useState('');
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Session | null>(null);
  const [manualOpen, setManualOpen] = useState(false);
  const [absenceOpen, setAbsenceOpen] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const query = new URLSearchParams({ from, to, limit: '500' });
      if (employeeId) query.set('employeeId', employeeId);
      if (status) query.set('status', status);
      const [attendance, employeeData] = await Promise.all([
        api.request<{ sessions: Session[] }>(`/api/v1/admin/attendance?${query}`),
        employees.length
          ? Promise.resolve({ employees })
          : api.request<{ employees: Employee[] }>('/api/v1/admin/employees?status=active&limit=500&offset=0'),
      ]);
      setSessions(attendance.sessions ?? []);
      setEmployees(employeeData.employees ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load attendance');
    } finally {
      setLoading(false);
    }
  }, [from, to, employeeId, status, employees]);

  useEffect(() => { void load(); }, [load]);

  async function approve(session: Session) {
    await api.request(`/api/v1/admin/attendance/${session.id}/approve`, { method: 'POST', body: {} });
    setEditing(null);
    await load();
  }

  async function remove(session: Session) {
    if (!confirm(`Delete this time entry for ${session.employeeName}? Raw scans and audit history will be retained.`)) return;
    await api.request(`/api/v1/admin/attendance/${session.id}/delete`, {
      method: 'POST',
      body: { reason: 'Attendance entry removed from web dashboard' },
    });
    setEditing(null);
    await load();
  }

  async function exportCsv() {
    const query = new URLSearchParams({ from, to });
    if (employeeId) query.set('employeeId', employeeId);
    await api.downloadGet(`/api/v1/admin/export?${query}`, `attendance-${from}-${to}.csv`);
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title="Attendance"
        actions={
          <>
            <Button variant="secondary" onClick={() => void exportCsv()}><Download className="h-4 w-4" /> Export CSV</Button>
            <Button variant="secondary" onClick={() => setAbsenceOpen(true)}>Mark absent</Button>
            <Button onClick={() => setManualOpen(true)}><Plus className="h-4 w-4" /> Add time</Button>
          </>
        }
      />

      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-end gap-2 border-b border-line px-4 py-3">
          <Input label="From" type="date" value={from} onChange={(event) => setFrom(event.target.value)} className="h-9 w-36" />
          <Input label="To" type="date" value={to} onChange={(event) => setTo(event.target.value)} className="h-9 w-36" />
          <Select label="Worker" value={employeeId} onChange={(event) => setEmployeeId(event.target.value)} className="h-9 min-w-40">
            <option value="">All workers</option>
            {employees.map((employee) => <option key={employee.id} value={employee.id}>{employee.name}</option>)}
          </Select>
          <Select label="Status" value={status} onChange={(event) => setStatus(event.target.value)} className="h-9 min-w-32">
            <option value="">All statuses</option>
            <option value="open">Open</option>
            <option value="closed">Closed</option>
            <option value="incomplete">Incomplete</option>
          </Select>
          <Button variant="secondary" onClick={() => void load()}>Apply</Button>
          <span className="ml-auto text-[11px] text-muted">{sessions.length} sessions</span>
        </div>

        {loading ? <div className="flex justify-center py-16"><Spinner /></div> : error ? <Empty>{error}</Empty> : sessions.length ? (
          <TableWrap>
            <table className="w-full min-w-[900px]">
              <thead><tr><th className="th">Date</th><th className="th">Worker</th><th className="th">Clock in</th><th className="th">Clock out</th><th className="th">Hours</th><th className="th">Status</th><th className="th">Review</th><th className="th" /></tr></thead>
              <tbody>
                {sessions.map((session) => (
                  <tr key={session.id}>
                    <td className="td font-mono text-[11px]">{session.workDate}</td>
                    <td className="td"><strong>{session.employeeName}</strong> <span className="text-muted">#{session.employeeCode}</span></td>
                    <td className="td">{fmtTime(session.checkInAt)}</td>
                    <td className="td">{fmtTime(session.checkOutAt)}</td>
                    <td className="td">{hours(session.workedMinutes)}</td>
                    <td className="td"><Badge tone={session.status === 'closed' ? 'green' : session.status === 'incomplete' ? 'red' : 'amber'}>{session.status}</Badge></td>
                    <td className="td"><Badge tone={session.reviewStatus === 'approved' ? 'green' : 'neutral'}>{session.reviewStatus === 'approved' ? 'Approved' : 'Needs review'}</Badge></td>
                    <td className="td text-right"><Button size="sm" variant="secondary" onClick={() => setEditing(session)}><Pencil className="h-3 w-3" /> Edit</Button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No attendance in this date range.</Empty>}
      </Card>

      {editing ? (
        <TimesModal
          session={editing}
          onClose={() => setEditing(null)}
          onSaved={async () => { setEditing(null); await load(); }}
          onApprove={approve}
          onDelete={remove}
        />
      ) : null}
      {manualOpen ? (
        <ManualModal employees={employees} onClose={() => setManualOpen(false)} onSaved={async () => { setManualOpen(false); await load(); }} />
      ) : null}
      {absenceOpen ? (
        <AbsenceModal employees={employees} onClose={() => setAbsenceOpen(false)} onSaved={async () => { setAbsenceOpen(false); await load(); }} />
      ) : null}
    </div>
  );
}

function TimesModal({
  session, onClose, onSaved, onApprove, onDelete,
}: {
  session: Session;
  onClose: () => void;
  onSaved: () => Promise<void>;
  onApprove: (session: Session) => Promise<void>;
  onDelete: (session: Session) => Promise<void>;
}) {
  const [checkIn, setCheckIn] = useState(localInput(session.checkInAt));
  const [checkOut, setCheckOut] = useState(localInput(session.checkOutAt));
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    try {
      const checkInDate = zonedToUtc(checkIn);
      const checkOutDate = zonedToUtc(checkOut);
      if (!checkInDate) throw new Error('Clock in is required.');
      if (checkOutDate && checkOutDate <= checkInDate) throw new Error('Clock out must be after clock in.');
      await api.request(`/api/v1/admin/attendance/${session.id}/times`, {
        method: 'PATCH',
        body: {
          employeeId: session.employeeId,
          checkInAt: checkInDate.toISOString(),
          checkOutAt: checkOutDate?.toISOString() ?? null,
        },
      });
      await onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save times');
    } finally {
      setPending(false);
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title="Edit clock times"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" form="times-form" disabled={pending}>{pending ? 'Saving…' : 'Save times'}</Button>
        </>
      }
    >
      <form id="times-form" className="space-y-4" onSubmit={save}>
        <p className="rounded-xl bg-canvas px-3 py-2 text-[11px] text-muted">{session.employeeName} · {session.workDate}</p>
        <div className="grid gap-4 sm:grid-cols-2">
          <Input label="Clock in" type="datetime-local" value={checkIn} onChange={(event) => setCheckIn(event.target.value)} required />
          <Input label="Clock out" type="datetime-local" value={checkOut} onChange={(event) => setCheckOut(event.target.value)} />
        </div>
        {error ? <p className="rounded-xl border border-danger/20 bg-danger-soft px-3 py-2 text-[11px] text-danger">{error}</p> : null}
        <div className="flex flex-wrap gap-2 border-t border-line pt-3">
          <Button
            variant="secondary"
            size="sm"
            disabled={session.status === 'open' || session.reviewStatus === 'approved'}
            onClick={() => void onApprove(session)}
          >
            {session.reviewStatus === 'approved' ? 'Approved' : 'Approve'}
          </Button>
          <Button variant="danger" size="sm" onClick={() => void onDelete(session)}>Delete</Button>
        </div>
      </form>
    </Modal>
  );
}

function ManualModal({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => Promise<void> }) {
  const [employeeId, setEmployeeId] = useState(employees[0]?.id ?? '');
  const [checkIn, setCheckIn] = useState(`${isoDate()}T09:00`);
  const [checkOut, setCheckOut] = useState('');
  const [reason, setReason] = useState('Administrator time entry');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    try {
      const inDate = zonedToUtc(checkIn);
      const outDate = zonedToUtc(checkOut);
      if (!inDate) throw new Error('Clock in is required.');
      if (outDate && outDate <= inDate) throw new Error('Clock out must be after clock in.');
      await api.request('/api/v1/admin/corrections/manual-session', {
        method: 'POST',
        body: {
          employeeId,
          checkInAt: inDate.toISOString(),
          ...(outDate ? { checkOutAt: outDate.toISOString() } : {}),
          reason: reason.trim(),
        },
      });
      await onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save entry');
    } finally {
      setPending(false);
    }
  }

  return (
    <Modal open onClose={onClose} title="Add time entry" footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button type="submit" form="manual-form" disabled={pending}>{pending ? 'Saving…' : 'Save entry'}</Button></>}>
      <form id="manual-form" className="space-y-4" onSubmit={save}>
        <Select label="Worker" value={employeeId} onChange={(event) => setEmployeeId(event.target.value)} required>
          {employees.filter((employee) => employee.status === 'active').map((employee) => <option key={employee.id} value={employee.id}>{employee.name} (#{employee.employeeCode})</option>)}
        </Select>
        <div className="grid gap-4 sm:grid-cols-2">
          <Input label="Clock in" type="datetime-local" value={checkIn} onChange={(event) => setCheckIn(event.target.value)} required />
          <Input label="Clock out" type="datetime-local" value={checkOut} onChange={(event) => setCheckOut(event.target.value)} />
        </div>
        <Input label="Reason" value={reason} onChange={(event) => setReason(event.target.value)} required />
        {error ? <p className="rounded-xl border border-danger/20 bg-danger-soft px-3 py-2 text-[11px] text-danger">{error}</p> : null}
      </form>
    </Modal>
  );
}

function AbsenceModal({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => Promise<void> }) {
  const [employeeId, setEmployeeId] = useState(employees[0]?.id ?? '');
  const [workDate, setWorkDate] = useState(isoDate());
  const [note, setNote] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    try {
      await api.request('/api/v1/admin/attendance/absence', { method: 'POST', body: { employeeId, workDate, note: note.trim() } });
      await onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not mark absence');
    } finally {
      setPending(false);
    }
  }

  return (
    <Modal open onClose={onClose} title="Mark worker absent" footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button variant="danger" type="submit" form="absence-form" disabled={pending}>{pending ? 'Saving…' : 'Mark absent'}</Button></>}>
      <form id="absence-form" className="space-y-4" onSubmit={save}>
        <Select label="Worker" value={employeeId} onChange={(event) => setEmployeeId(event.target.value)} required>
          {employees.filter((employee) => employee.status === 'active').map((employee) => <option key={employee.id} value={employee.id}>{employee.name} (#{employee.employeeCode})</option>)}
        </Select>
        <Input label="Date" type="date" value={workDate} onChange={(event) => setWorkDate(event.target.value)} required />
        <Textarea label="Note" value={note} onChange={(event) => setNote(event.target.value)} />
        {error ? <p className="rounded-xl border border-danger/20 bg-danger-soft px-3 py-2 text-[11px] text-danger">{error}</p> : null}
      </form>
    </Modal>
  );
}
