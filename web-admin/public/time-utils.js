export function timeChanges(session, checkIn, checkOut) {
  const originalIn = new Date(session.checkInAt).toISOString();
  const originalOut = session.checkOutAt
    ? new Date(session.checkOutAt).toISOString()
    : null;
  const changes = [];

  if (checkIn !== originalIn) changes.push(['check_in', checkIn]);
  if (checkOut && checkOut !== originalOut) {
    changes.push(['check_out', checkOut]);
  }

  // Moving a complete shift past its old checkout must update checkout first;
  // otherwise the API rejects the new check-in against the still-old value.
  if (
    changes.length === 2 &&
    originalOut &&
    new Date(checkIn) >= new Date(originalOut)
  ) {
    changes.reverse();
  }

  return changes;
}
