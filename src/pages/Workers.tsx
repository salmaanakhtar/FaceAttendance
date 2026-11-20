import { Plus, Search } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { Badge, Button, Card, Empty, Input, Modal, PageHeader, Select, Spinner, TableWrap, Textarea } from '../components/ui';
import type { Employee } from '../lib/types';

const DAYS = [
  ['mon', 'Mon'], ['tue', 'Tue'], ['wed', 'Wed'], ['thu', 'Thu'],
  ['fri', 'Fri'], ['sat', 'Sat'], ['sun', 'Sun'],
] as const;

export function Workers() {
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<Employee | null | undefined>(undefined);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await api.request<{ employees: Employee[] }>('/api/v1/admin/employees?status=all&limit=200&offset=0');
      setEmployees(data.employees ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load workers');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const visible = employees.filter((employee) =>
    `${employee.name} ${employee.employeeCode} ${employee.schedule?.department ?? ''}`
      .toLowerCase()
      .includes(search.toLowerCase()),
  );

  async function deactivate(employee: Employee) {
    if (!confirm(`Deactivate ${employee.name}? They will no longer be able to clock in.`)) return;
    await api.request(`/api/v1/admin/employees/${employee.id}/deactivate`, { method: 'POST', body: {} });
    await load();
  }

  async function remove(employee: Employee) {
    if (!confirm(`Delete ${employee.name}? Attendance and audit history will be retained.`)) return;
    await api.request(`/api/v1/admin/employees/${employee.id}/delete`, { method: 'POST', body: {} });
    await load();
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title="Workers"
        actions={<Button onClick={() => setEditing(null)}><Plus className="h-4 w-4" /> Add worker</Button>}
      />

      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-4 py-3">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search workers"
              className="field h-9 w-full pl-9 text-[11px] sm:w-64"
            />
          </div>
          <Badge>{visible.length} workers</Badge>
        </div>

        {loading ? <div className="flex justify-center py-16"><Spinner /></div> : error ? (
          <Empty>{error}</Empty>
        ) : visible.length ? (
          <TableWrap>
            <table className="w-full min-w-[820px]">
              <thead><tr><th className="th">Worker</th><th className="th">Code</th><th className="th">Department</th><th className="th">Weekly hours</th><th className="th">Rate</th><th className="th">Face</th><th className="th">Status</th><th className="th" /></tr></thead>
              <tbody>
                {visible.map((employee) => (
                  <tr key={employee.id}>
                    <td className="td"><strong>{employee.name}</strong><br /><span className="text-[10px] text-muted">{employee.email ?? '—'}</span></td>
                    <td className="td font-mono text-[11px]">{employee.employeeCode}</td>
                    <td className="td">{employee.schedule?.department ?? '—'}</td>
                    <td className="td">{employee.schedule?.hoursPerWeek ?? '—'}</td>
                    <td className="td">R {Number(employee.schedule?.hourlyRate ?? 30.23).toFixed(2)}</td>
                    <td className="td"><Badge tone={employee.enrolled ? 'green' : 'amber'}>{employee.enrolled ? 'Enrolled' : 'Not enrolled'}</Badge></td>
                    <td className="td"><Badge tone={employee.status === 'active' ? 'green' : 'neutral'}>{employee.status}</Badge></td>
                    <td className="td text-right"><Button size="sm" variant="secondary" onClick={() => setEditing(employee)}>Edit</Button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No matching workers.</Empty>}
      </Card>

      {editing !== undefined ? (
        <WorkerModal
          employee={editing}
          onClose={() => setEditing(undefined)}
          onSaved={async () => { setEditing(undefined); await load(); }}
          onDeactivate={deactivate}
          onDelete={remove}
        />
      ) : null}
    </div>
  );
}

function WorkerModal({
  employee,
  onClose,
  onSaved,
  onDeactivate,
  onDelete,
}: {
  employee: Employee | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
  onDeactivate: (employee: Employee) => Promise<void>;
  onDelete: (employee: Employee) => Promise<void>;
}) {
  const schedule = employee?.schedule ?? {};
  const [name, setName] = useState(employee?.name ?? '');
  const [code, setCode] = useState(employee?.employeeCode ?? '');
  const [email, setEmail] = useState(employee?.email ?? '');
  const [department, setDepartment] = useState(String(schedule.department ?? ''));
  const [hoursPerWeek, setHoursPerWeek] = useState(String(schedule.hoursPerWeek ?? 40));
  const [rate, setRate] = useState(String(schedule.hourlyRate ?? 30.23));
  const [firstName, setFirstName] = useState(String(schedule.firstName ?? ''));
  const [surname, setSurname] = useState(String(schedule.surname ?? ''));
  const [identityNumber, setIdentityNumber] = useState(String(schedule.identityNumber ?? ''));
  const [occupation, setOccupation] = useState(String(schedule.occupation ?? ''));
  const [startDate, setStartDate] = useState(String(schedule.startDate ?? ''));
  const [paymentMethod, setPaymentMethod] = useState(String(schedule.paymentMethod ?? ''));
  const [employerAddress, setEmployerAddress] = useState(String(schedule.employerAddress ?? ''));
  const [workDays, setWorkDays] = useState<string[]>(schedule.workDays ?? ['mon', 'tue', 'wed', 'thu', 'fri']);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    if (!workDays.length) {
      setError('Select at least one scheduled workday.');
      return;
    }
    setPending(true);
    setError(null);
    const nextSchedule = {
      ...schedule,
      department: department.trim(),
      hoursPerWeek: Number(hoursPerWeek),
      hourlyRate: Number(rate),
      workDays,
      firstName: firstName.trim(),
      surname: surname.trim(),
      identityNumber: identityNumber.trim(),
      occupation: occupation.trim(),
      startDate,
      paymentMethod: paymentMethod.trim(),
      employerAddress: employerAddress.trim(),
    };
    try {
      const body: Record<string, unknown> = {
        name: name.trim(),
        email: email.trim() || null,
        schedule: nextSchedule,
      };
      if (!employee) body.employeeCode = code.trim();
      await api.request(employee ? `/api/v1/admin/employees/${employee.id}` : '/api/v1/admin/employees', {
        method: employee ? 'PATCH' : 'POST',
        body,
      });
      await onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save worker');
    } finally {
      setPending(false);
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={employee ? 'Edit worker' : 'Add worker'}
      wide
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" form="worker-form" disabled={pending}>{pending ? 'Saving…' : 'Save worker'}</Button>
        </>
      }
    >
      <form id="worker-form" className="grid gap-4 sm:grid-cols-2" onSubmit={save}>
        <Input label="Full name" value={name} onChange={(event) => setName(event.target.value)} required />
        <Input label="Worker code" value={code} onChange={(event) => setCode(event.target.value)} disabled={Boolean(employee)} required={!employee} inputMode="numeric" />
        <Input label="Email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
        <Input label="Department" value={department} onChange={(event) => setDepartment(event.target.value)} required />
        <Input label="Weekly hours" type="number" min="0" max="168" step="0.25" value={hoursPerWeek} onChange={(event) => setHoursPerWeek(event.target.value)} required />
        <Input label="Normal hourly rate (R)" type="number" min="0" step="0.01" value={rate} onChange={(event) => setRate(event.target.value)} required />
        <Input label="First name" value={firstName} onChange={(event) => setFirstName(event.target.value)} />
        <Input label="Surname" value={surname} onChange={(event) => setSurname(event.target.value)} />
        <Input label="ID number" value={identityNumber} onChange={(event) => setIdentityNumber(event.target.value)} />
        <Input label="Occupation" value={occupation} onChange={(event) => setOccupation(event.target.value)} />
        <Input label="Date engaged" type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} />
        <Select label="Payment method" value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}>
          <option value="">Not set</option>
          <option>Bank transfer</option>
          <option>Cash</option>
          <option>EFT</option>
        </Select>
        <Textarea label="Employer address" value={employerAddress} onChange={(event) => setEmployerAddress(event.target.value)} className="sm:col-span-2" />
        <div className="sm:col-span-2">
          <p className="label mb-2">Scheduled workdays</p>
          <div className="flex flex-wrap gap-2">
            {DAYS.map(([value, label]) => (
              <label key={value} className="inline-flex items-center gap-1.5 text-[12px] text-ink">
                <input
                  type="checkbox"
                  checked={workDays.includes(value)}
                  onChange={(event) =>
                    setWorkDays((current) =>
                      event.target.checked ? [...current, value] : current.filter((day) => day !== value),
                    )
                  }
                />
                {label}
              </label>
            ))}
          </div>
        </div>
        {employee ? (
          <div className="sm:col-span-2 rounded-xl border border-line bg-canvas px-3 py-3 text-[11px] text-muted">
            Face enrollment is done from the mobile app. {employee.enrolled ? 'This worker has enrolled face samples.' : 'No Rekognition faces are enrolled yet.'}
          </div>
        ) : null}
        {error ? <p className="sm:col-span-2 rounded-xl border border-danger/20 bg-danger-soft px-3 py-2 text-[11px] text-danger">{error}</p> : null}
        {employee ? (
          <div className="sm:col-span-2 flex flex-wrap gap-2 border-t border-line pt-3">
            {employee.status === 'active' ? (
              <Button variant="secondary" size="sm" onClick={() => void onDeactivate(employee)}>Deactivate</Button>
            ) : null}
            <Button variant="danger" size="sm" onClick={() => void onDelete(employee)}>Delete</Button>
          </div>
        ) : null}
      </form>
    </Modal>
  );
}
