ALTER TABLE attendance_sessions
  ADD COLUMN review_status text NOT NULL DEFAULT 'needs_review'
    CHECK (review_status IN ('needs_review', 'approved')),
  ADD COLUMN reviewed_by uuid REFERENCES admins(id),
  ADD COLUMN reviewed_at timestamptz;

CREATE INDEX idx_sessions_review_status
  ON attendance_sessions (org_id, review_status, work_date DESC);
