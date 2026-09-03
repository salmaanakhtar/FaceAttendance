ALTER TABLE employee_leave
  DROP CONSTRAINT IF EXISTS employee_leave_leave_type_check;

ALTER TABLE employee_leave
  ADD CONSTRAINT employee_leave_leave_type_check
  CHECK (leave_type IN ('annual', 'sick', 'unpaid', 'other', 'absence'));
