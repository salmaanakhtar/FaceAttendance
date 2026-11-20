-- 008_rekognition_faces.sql
-- Server-side face enrollment metadata. The images themselves are sent to
-- AWS Rekognition; only FaceIds and quality metadata are stored here.

CREATE TABLE employee_faces (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            uuid NOT NULL REFERENCES orgs(id),
  employee_id       uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  collection_id     text NOT NULL,
  face_id           text NOT NULL,
  image_id          text,
  external_image_id text NOT NULL,
  quality           jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (collection_id, face_id)
);

CREATE INDEX idx_employee_faces_employee
  ON employee_faces (org_id, employee_id);
