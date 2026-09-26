CREATE TABLE employee_leave (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      uuid NOT NULL REFERENCES orgs(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  start_date  date NOT NULL,
  end_date    date NOT NULL,
  leave_type  text NOT NULL CHECK (leave_type IN ('annual','sick','unpaid','other')),
  status      text NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  note        text,
  created_by  uuid NOT NULL REFERENCES admins(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);

CREATE INDEX idx_employee_leave_org_dates
  ON employee_leave (org_id, start_date, end_date);
CREATE INDEX idx_employee_leave_employee_dates
  ON employee_leave (employee_id, start_date DESC);
