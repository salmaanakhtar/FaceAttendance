import { api } from './api';

export function timezone(): string {
  return api.org?.timezone || 'Africa/Johannesburg';
}

export function isoDate(date: Date = new Date()): string {
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: timezone(),
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

export function shiftDate(value: string, days: number): string {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day + days, 12)).toISOString().slice(0, 10);
}

export function mondayOf(value: string = isoDate()): string {
  const day = new Date(`${value}T12:00:00Z`).getUTCDay();
  return shiftDate(value, -((day + 6) % 7));
}

export function monthRange(value: string = isoDate().slice(0, 7)): { from: string; to: string } {
  const [year, month] = value.split('-').map(Number);
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return { from: `${value}-01`, to: `${value}-${String(last).padStart(2, '0')}` };
}

export function fmtTime(value?: string | null): string {
  if (!value) return '—';
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: timezone(),
  }).format(new Date(value));
}

export function fmtDate(value?: string | null): string {
  if (!value) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: timezone(),
  }).format(new Date(`${String(value).slice(0, 10)}T12:00:00Z`));
}

export function hours(minutes?: number | null): string {
  const total = Number(minutes ?? 0);
  return `${Math.floor(total / 60)}h ${Math.round(total % 60)}m`;
}

export function money(value?: number | null): string {
  if (value == null) return '—';
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

export function localInput(iso?: string | null): string {
  if (!iso) return '';
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: timezone(),
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  })
    .format(new Date(iso))
    .replace(' ', 'T');
}

export function zonedToUtc(value: string): Date | null {
  if (!value) return null;
  const [datePart, timePart] = value.split('T');
  const [year, month, day] = datePart.split('-').map(Number);
  const [hour, minute] = timePart.split(':').map(Number);
  const target = Date.UTC(year, month - 1, day, hour, minute);
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone(),
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  let ts = target;
  for (let i = 0; i < 2; i += 1) {
    const parts = Object.fromEntries(
      formatter.formatToParts(new Date(ts)).map((part) => [part.type, part.value]),
    );
    const asLocal = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour) % 24,
      Number(parts.minute),
    );
    ts += target - asLocal;
  }
  return new Date(ts);
}
