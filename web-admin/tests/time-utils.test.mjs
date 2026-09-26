import test from 'node:test';
import assert from 'node:assert/strict';
import { timeChanges } from '../public/time-utils.js';

const session = {
  checkInAt: '2026-09-26T06:00:00.000Z',
  checkOutAt: '2026-09-26T15:00:00.000Z',
};

test('returns only the clock-in correction when only clock-in changes', () => {
  assert.deepEqual(
    timeChanges(
      session,
      '2026-09-26T05:30:00.000Z',
      '2026-09-26T15:00:00.000Z',
    ),
    [['check_in', '2026-09-26T05:30:00.000Z']],
  );
});

test('moves checkout first when the whole shift moves beyond the old checkout', () => {
  assert.deepEqual(
    timeChanges(
      session,
      '2026-09-26T16:00:00.000Z',
      '2026-09-26T18:00:00.000Z',
    ),
    [
      ['check_out', '2026-09-26T18:00:00.000Z'],
      ['check_in', '2026-09-26T16:00:00.000Z'],
    ],
  );
});

test('moves check-in first when the whole shift moves before the old check-in', () => {
  assert.deepEqual(
    timeChanges(
      session,
      '2026-09-26T02:00:00.000Z',
      '2026-09-26T04:00:00.000Z',
    ),
    [
      ['check_in', '2026-09-26T02:00:00.000Z'],
      ['check_out', '2026-09-26T04:00:00.000Z'],
    ],
  );
});
