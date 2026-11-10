-- 009_min_interval_10s.sql
-- The duplicate-scan guard moved from a 1-minute window to 10 seconds and is
-- now expressed in seconds. Normalise existing employee schedules so future
-- edits keep the new key instead of the legacy minute value.

UPDATE employees
SET schedule = (schedule - 'minIntervalMinutes')
  || jsonb_build_object('minIntervalSeconds', 10)
WHERE schedule ? 'minIntervalMinutes';
