import { describe, expect, it } from 'vitest';
import { selectFaceMatch } from './rekognition.js';

const matches = (rows: Array<[string, number]>) =>
  rows.map(([employeeId, similarity], index) => ({
    employeeId,
    similarity,
    faceId: `face-${index}`,
  }));

describe('Rekognition match selection', () => {
  it('accepts a match at or above the threshold', () => {
    const result = selectFaceMatch(matches([['e1', 92]]), 90, 2);
    expect(result?.employeeId).toBe('e1');
    expect(result?.ambiguous).toBe(false);
  });

  it('rejects a match below the threshold', () => {
    expect(selectFaceMatch(matches([['e1', 89.9]]), 90, 2)).toBeNull();
  });

  it('marks two close distinct employees ambiguous', () => {
    const result = selectFaceMatch(matches([['e1', 94], ['e2', 93.5]]), 90, 2);
    expect(result?.employeeId).toBe('e1');
    expect(result?.ambiguous).toBe(true);
  });

  it('does not treat two faces of the same employee as rivals', () => {
    const result = selectFaceMatch(matches([['e1', 94], ['e1', 93.5]]), 90, 2);
    expect(result?.ambiguous).toBe(false);
  });

  it('ignores a runner-up more than the margin below', () => {
    const result = selectFaceMatch(matches([['e1', 95], ['e2', 90]]), 90, 2);
    expect(result?.ambiguous).toBe(false);
  });
});
