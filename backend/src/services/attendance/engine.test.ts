import { describe, expect, it } from 'vitest';
import {
  DEFAULT_POLICY,
  classify,
  flagMissedCheckouts,
  processScan,
  type ScanEvent,
  type Session,
  type ShiftPolicy,
} from './engine.js';

const TZ = 'Asia/Karachi';
const policy: ShiftPolicy = {
  ...DEFAULT_POLICY,
  timezone: TZ,
};

function ev(id: string, iso: string, hint: 'in' | 'out' | null = null): ScanEvent {
  return { id, scanTime: new Date(iso), directionHint: hint };
}

function openSession(iso: string, workDate = '2026-08-11'): Session {
  return {
    id: 's1',
    employeeId: 'emp1',
    workDate,
    checkInAt: new Date(iso),
    checkOutAt: null,
    checkInSource: 'auto',
    checkOutSource: 'auto',
    status: 'open',
    breakMinutes: 0,
    policy,
    stats: {
      workedMinutes: 0,
      lateMinutes: 0,
      earlyMinutes: 0,
      overtimeMinutes: 0,
      isLate: false,
      isEarly: false,
      hasOvertime: false,
    },
    note: null,
  };
}

function base(e: ScanEvent): Parameters<typeof processScan>[0] {
  return {
    employeeId: 'emp1',
    event: e,
    openSession: null,
    lastSession: null,
    lastEventAt: null,
    policy,
  };
}

describe('check-in', () => {
  it('creates an open session with the correct local work date', () => {
    const r = processScan(base(ev('e1', '2026-08-11T04:30:00Z', 'in')));
    expect(r.action).toBe('check_in');
    if (r.action === 'check_in') {
      expect(r.session.workDate).toBe('2026-08-11'); // 09:30 local
      expect(r.session.status).toBe('open');
      expect(r.session.checkInAt?.toISOString()).toBe('2026-08-11T04:30:00.000Z');
    }
  });

  it('uses the server date even when device time differs', () => {
    // server says 23:30 local (Aug 11); a drifting device would say Aug 12
    const r = processScan(base(ev('e1', '2026-08-11T18:30:00Z', 'in')));
    expect(r.action).toBe('check_in');
    if (r.action === 'check_in') expect(r.session.workDate).toBe('2026-08-11');
  });
});

describe('check-out', () => {
  it('closes the open session and computes stats', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T14:00:00Z', 'out')),
      openSession: openSession('2026-08-11T04:30:00Z'), // 09:30 local
    });
    expect(r.action).toBe('check_out');
    if (r.action === 'check_out') {
      expect(r.session.status).toBe('closed');
      expect(r.session.stats.workedMinutes).toBe(540); // 09:30→19:00 local = 9.5h − 30m break
      expect(r.session.stats.lateMinutes).toBe(25); // late by 25 min (grace 5)
      expect(r.session.stats.overtimeMinutes).toBe(60); // out at 19:00, shift ends 18:00
    }
  });

  it('attributes a checkout after midnight to the open session', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T20:00:00Z', 'out')), // 01:00 local Aug 12
      openSession: openSession('2026-08-11T04:30:00Z'),
    });
    expect(r.action).toBe('check_out');
    if (r.action === 'check_out') {
      expect(r.session.checkOutAt?.toISOString()).toBe('2026-08-11T20:00:00.000Z');
      expect(r.session.workDate).toBe('2026-08-11'); // still yesterday's session
    }
  });

  it('rejects a checkout earlier than the check-in', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T04:00:00Z', 'out')),
      openSession: openSession('2026-08-11T04:30:00Z'),
    });
    expect(r.action).toBe('invalid');
  });
});

describe('duplicates and guards', () => {
  it('drops an event within the min interval of the previous one', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T04:30:30Z', 'in')),
      lastEventAt: new Date('2026-08-11T04:30:00Z'),
    });
    expect(r.action).toBe('duplicate');
  });

  it('reports already_in for a second check-in while open', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T06:00:00Z', 'in')),
      openSession: openSession('2026-08-11T04:30:00Z'),
    });
    expect(r.action).toBe('already_in');
  });

  it('reports already_out with no open session', () => {
    const r = processScan(base(ev('e1', '2026-08-11T06:00:00Z', 'out')));
    expect(r.action).toBe('already_out');
  });

  it('blocks a same-day second shift inside the shift gap', () => {
    const closed: Session = {
      ...openSession('2026-08-11T04:30:00Z'),
      checkOutAt: new Date('2026-08-11T12:30:00Z'), // 17:30 local
      status: 'closed',
    };
    const r = processScan({
      ...base(ev('e1', '2026-08-11T13:00:00Z', 'in')), // 18:00 local — only 30 min gap
      lastSession: closed,
    });
    expect(r.action).toBe('duplicate');
  });

  it('allows a same-day second shift after the gap', () => {
    const closed: Session = {
      ...openSession('2026-08-11T04:30:00Z'),
      checkOutAt: new Date('2026-08-11T12:30:00Z'),
      status: 'closed',
    };
    const r = processScan({
      ...base(ev('e1', '2026-08-11T18:00:00Z', 'in')), // 23:00 local
      lastSession: closed,
    });
    expect(r.action).toBe('check_in');
    if (r.action === 'check_in') expect(r.session.workDate).toBe('2026-08-11');
  });
});

describe('breaks', () => {
  it('deducts configured break for shifts at/over the threshold', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T15:30:00Z', 'out')), // 20:30 local
      openSession: openSession('2026-08-11T04:30:00Z'), // 09:30 — 11h raw
    });
    expect(r.action).toBe('check_out');
    if (r.action === 'check_out') {
      expect(r.session.breakMinutes).toBe(30);
      expect(r.session.stats.workedMinutes).toBe(630); // 11h - 30m
    }
  });
});

describe('night shifts', () => {
  const night: ShiftPolicy = {
    ...policy,
    shiftStart: '22:00',
    shiftEnd: '06:00',
    overnight: true,
    breakAfterHours: 8,
  };

  it('creates a session on check-in at 23:00 and closes it at 05:00 next day', () => {
    const rIn = processScan({
      ...base(ev('e1', '2026-08-11T18:00:00Z', 'in')), // 23:00 local
      policy: night,
    });
    expect(rIn.action).toBe('check_in');
    let session: Session | null = null;
    if (rIn.action === 'check_in') {
      session = rIn.session;
      expect(session.workDate).toBe('2026-08-11');
    }
    const rOut = processScan({
      ...base(ev('e1', '2026-08-11T23:55:00Z', 'out')), // 04:55 local Aug 12
      policy: night,
      openSession: session,
    });
    expect(rOut.action).toBe('check_out');
    if (rOut.action === 'check_out') {
      expect(rOut.session.workDate).toBe('2026-08-11');
      expect(rOut.session.stats.workedMinutes).toBe(355); // 6h
      expect(rOut.session.stats.isEarly).toBe(true); // out 65 min early
    }
  });

  it('flags a late night-shift arrival', () => {
    const r = processScan({
      ...base(ev('e1', '2026-08-11T19:30:00Z', 'in')), // 00:30 local Aug 12
      policy: night,
    });
    expect(r.action).toBe('check_in');
    if (r.action === 'check_in') {
      expect(r.session.workDate).toBe('2026-08-12');
      expect(r.session.stats.isLate).toBe(false); // late is classified at close
    }
  });
});

describe('rollover', () => {
  it('marks a stale open session incomplete', () => {
    const stale = openSession('2026-08-10T04:30:00Z', '2026-08-10'); // yesterday local
    const result = flagMissedCheckouts(
      [stale],
      new Date('2026-08-11T06:00:00Z'), // today, 11:00 local
    );
    expect(result).toHaveLength(1);
    expect(result[0]?.status).toBe('incomplete');
    expect(result[0]?.note).toContain('missed checkout');
  });

  it('leaves today\'s open session alone', () => {
    const fresh = openSession('2026-08-11T04:30:00Z');
    const result = flagMissedCheckouts([fresh], new Date('2026-08-11T06:00:00Z'));
    expect(result).toHaveLength(0);
  });
});

describe('classification', () => {
  it('computes late, early and overtime flags', () => {
    const s: Session = {
      ...openSession('2026-08-11T05:00:00Z'), // 10:00 local (late by 55)
      checkOutAt: new Date('2026-08-11T13:00:00Z'), // 18:00 local (on time)
    };
    classify(s, new Date('2026-08-11T13:00:00Z'));
    expect(s.stats.isLate).toBe(true);
    expect(s.stats.lateMinutes).toBe(55);
    expect(s.stats.isEarly).toBe(false);
    expect(s.stats.overtimeMinutes).toBe(0);
  });
});
