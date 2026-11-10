ALTER TABLE attendance_sessions
  ADD COLUMN voided_at timestamptz,
  ADD COLUMN voided_by uuid REFERENCES admins(id),
  ADD COLUMN void_reason text;

CREATE INDEX idx_sessions_active_org_date
  ON attendance_sessions (org_id, work_date DESC)
  WHERE voided_at IS NULL;
