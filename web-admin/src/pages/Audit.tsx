import { Search } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { fmtTime } from '../lib/format';
import type { AuditEvent } from '../lib/types';
import { Badge, Button, Card, Empty, PageHeader, Spinner, TableWrap } from '../components/ui';

export function Audit() {
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await api.request<{ events: AuditEvent[] }>('/api/v1/admin/audit?limit=200');
      setEvents(data.events ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load audit log');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const visible = events.filter((event) =>
    `${event.action} ${event.actorType} ${event.targetType ?? ''} ${JSON.stringify(event.details ?? {})}`
      .toLowerCase()
      .includes(search.toLowerCase()),
  );

  return (
    <div className="space-y-5">
      <PageHeader title="Audit" actions={<Button variant="secondary" onClick={() => void load()}>Refresh</Button>} />
      <Card className="overflow-hidden">
        <div className="flex items-center justify-between gap-2 border-b border-line px-4 py-3">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Filter activity" className="field h-9 w-full pl-9 text-[11px] sm:w-64" />
          </div>
          <Badge>{visible.length} events</Badge>
        </div>
        {loading ? <div className="flex justify-center py-16"><Spinner /></div> : error ? <Empty>{error}</Empty> : visible.length ? (
          <TableWrap>
            <table className="w-full min-w-[900px]">
              <thead><tr><th className="th">Time</th><th className="th">Action</th><th className="th">Actor</th><th className="th">Target</th><th className="th">Details</th></tr></thead>
              <tbody>
                {visible.map((event) => (
                  <tr key={event.id}>
                    <td className="td whitespace-nowrap">{fmtTime(event.createdAt)}</td>
                    <td className="td">{event.action.replaceAll('_', ' ')}</td>
                    <td className="td">{event.actorType}</td>
                    <td className="td">{event.targetType ?? '—'}</td>
                    <td className="td max-w-[320px] truncate" title={JSON.stringify(event.details ?? {})}>{JSON.stringify(event.details ?? {})}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        ) : <Empty>No matching audit activity.</Empty>}
      </Card>
    </div>
  );
}
