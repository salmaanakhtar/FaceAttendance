CREATE TABLE employee_absences (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      uuid NOT NULL REFERENCES orgs(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  work_date   date NOT NULL,
  note        text,
  created_by  uuid NOT NULL REFERENCES admins(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (org_id, employee_id, work_date)
);

CREATE INDEX idx_employee_absences_org_date
  ON employee_absences (org_id, work_date DESC);

-- Preserve absences recorded by v1.2.16/v1.2.17, but move their meaning out
-- of leave calculations. Legacy rows remain for their original audit links.
INSERT INTO employee_absences
  (org_id, employee_id, work_date, note, created_by, created_at)
SELECT DISTINCT ON (org_id, employee_id, start_date)
  org_id, employee_id, start_date, note, created_by, created_at
FROM employee_leave
WHERE leave_type = 'absence' AND status = 'approved'
ORDER BY org_id, employee_id, start_date, created_at
ON CONFLICT (org_id, employee_id, work_date) DO NOTHING;
