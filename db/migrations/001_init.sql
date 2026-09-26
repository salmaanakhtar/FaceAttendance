-- 001_init.sql — initial schema
-- All timestamps timestamptz (UTC storage); site-local dates derived at read time.

CREATE TABLE orgs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  timezone    text NOT NULL DEFAULT 'UTC',
  settings    jsonb NOT NULL DEFAULT '{}',
  encryption_key text NOT NULL DEFAULT 'dev',  -- org secret; key derived from it
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sites (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      uuid NOT NULL REFERENCES orgs(id),
  name        text NOT NULL,
  timezone    text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id           uuid NOT NULL REFERENCES orgs(id),
  site_id          uuid REFERENCES sites(id),
  name             text NOT NULL DEFAULT 'kiosk',
  device_key_hash  text NOT NULL UNIQUE,
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled')),
  clock_offset_ms  bigint NOT NULL DEFAULT 0,
  last_seen_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE admins (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL REFERENCES orgs(id),
  name          text NOT NULL,
  username      text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role          text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin','owner')),
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE admin_sessions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id   uuid NOT NULL REFERENCES admins(id),
  device_id  uuid REFERENCES devices(id),
  token_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz
);

CREATE TABLE employees (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id              uuid NOT NULL REFERENCES orgs(id),
  site_id             uuid REFERENCES sites(id),
  employee_code       text NOT NULL,
  name                text NOT NULL,
  email               text,
  phone               text,
  status              text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','deleted')),
  schedule            jsonb NOT NULL DEFAULT '{}',
  face_template       bytea,
  template_version    int,
  enrollment_quality  jsonb,
  enrolled_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (org_id, employee_code),
  UNIQUE (org_id, email)
);

-- Raw scanner events. INSERT-ONLY. Corrections never touch this table.
CREATE TABLE scan_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id           uuid NOT NULL,
  device_id        uuid NOT NULL REFERENCES devices(id),
  employee_id      uuid REFERENCES employees(id),
  scan_time        timestamptz NOT NULL,          -- SERVER time (authoritative)
  device_time      timestamptz,                   -- device clock (metadata only)
  direction        text CHECK (direction IN ('in','out')),
  confidence       numeric(6,5),
  liveness_score   numeric(5,4),
  face_hash        text,
  dedupe_key       text NOT NULL UNIQUE,
  sync_state       text NOT NULL DEFAULT 'live' CHECK (sync_state IN ('live','offline','conflict')),
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_scan_events_employee_time ON scan_events (employee_id, scan_time);
CREATE INDEX idx_scan_events_device_time ON scan_events (device_id, scan_time);

-- Derived attendance sessions (one per shift block).
CREATE TABLE attendance_sessions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            uuid NOT NULL,
  employee_id       uuid NOT NULL REFERENCES employees(id),
  work_date         date NOT NULL,                -- site-local date of check-in
  check_in_at       timestamptz,
  check_out_at      timestamptz,
  check_in_source   text NOT NULL DEFAULT 'auto' CHECK (check_in_source IN ('auto','manual')),
  check_out_source  text NOT NULL DEFAULT 'auto' CHECK (check_out_source IN ('auto','manual')),
  status            text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','incomplete')),
  break_minutes     int NOT NULL DEFAULT 0,
  policy            jsonb NOT NULL DEFAULT '{}',
  stats             jsonb NOT NULL DEFAULT '{}',  -- late_minutes, early_minutes, overtime_minutes
  note              text,
  corrected         boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_sessions_employee_date ON attendance_sessions (employee_id, work_date DESC);
CREATE INDEX idx_sessions_org_date ON attendance_sessions (org_id, work_date DESC);

-- Append-only log of applied manual corrections (never deletes; supersedes).
CREATE TABLE attendance_corrections (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      uuid NOT NULL,
  session_id  uuid REFERENCES attendance_sessions(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  field       text NOT NULL,
  old_value   jsonb,
  new_value   jsonb,
  admin_id    uuid NOT NULL REFERENCES admins(id),
  reason      text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_corrections_employee ON attendance_corrections (employee_id, created_at);

-- Idempotency outcomes: dedupe_key -> final action, so replays return the
-- same result without re-running the engine.
CREATE TABLE scan_outcomes (
  dedupe_key text PRIMARY KEY,
  action     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Audit trail for everything that matters.
CREATE TABLE audit_events (
  id          bigserial PRIMARY KEY,
  org_id      uuid,
  actor_type  text NOT NULL CHECK (actor_type IN ('admin','device','system')),
  actor_id    text,
  action      text NOT NULL,
  target_type text,
  target_id   text,
  details     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_org_time ON audit_events (org_id, created_at DESC);
