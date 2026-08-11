/**
 * Timezone helpers. Server stores timestamptz (UTC). Site-local dates and
 * times are derived with Intl against the site timezone — no tz database
 * dependency, deterministic for any IANA zone including DST transitions.
 */

const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

export interface LocalParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  weekday: string;
  /** numeric UTC offset in minutes at this instant */
  offsetMinutes: number;
}

function partsOf(date: Date, timeZone: string): LocalParts {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    weekday: 'short',
    timeZoneName: 'shortOffset',
  });
  const parts: Record<string, string> = {};
  for (const p of fmt.formatToParts(date)) parts[p.type] = p.value;
  let hour = Number(parts.hour);
  if (hour === 24) hour = 0;
  const offsetRaw = parts.timeZoneName ?? 'GMT+0';
  const m = offsetRaw.match(/GMT([+-])(\d+):?(\d+)?/);
  let offsetMinutes = 0;
  if (m) {
    const sign = m[1] === '-' ? -1 : 1;
    offsetMinutes = sign * (Number(m[2]) * 60 + Number(m[3] ?? 0));
  }
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour,
    minute: Number(parts.minute),
    weekday: (parts.weekday ?? 'mon').toLowerCase().slice(0, 3),
    offsetMinutes,
  };
}

export function localDate(date: Date, timeZone: string): string {
  const p = partsOf(date, timeZone);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

export function localTime(date: Date, timeZone: string): string {
  const p = partsOf(date, timeZone);
  return `${String(p.hour).padStart(2, '0')}:${String(p.minute).padStart(2, '0')}`;
}

export function weekdayOf(date: Date, timeZone: string): string {
  return partsOf(date, timeZone).weekday;
}

/** Convert "HH:MM" (24h) local wall time into minutes since midnight. */
export function hmToMinutes(hm: string): number {
  const [h, m] = hm.split(':').map(Number);
  if (h === undefined || m === undefined || Number.isNaN(h) || Number.isNaN(m)) {
    throw new Error(`invalid HH:MM time: ${hm}`);
  }
  return h * 60 + m;
}

export function minutesToHm(minutes: number): string {
  const m = ((Math.round(minutes) % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

export function hoursMinutes(ms: number): string {
  const totalMin = Math.round(ms / 60000);
  const sign = totalMin < 0 ? '-' : '';
  const abs = Math.abs(totalMin);
  return `${sign}${Math.floor(abs / 60)}h ${abs % 60}m`;
}

export function startOfLocalDay(date: Date, timeZone: string): Date {
  const p = partsOf(date, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day) - p.offsetMinutes * 60000;
  return new Date(asUtc);
}

export function addDaysLocal(date: Date, timeZone: string, days: number): Date {
  const p = partsOf(date, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day + days) - p.offsetMinutes * 60000;
  return new Date(asUtc);
}

export const WEEKDAYS_LIST = WEEKDAYS;
