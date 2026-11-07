# AWS Rekognition face check-in

## Region

Rekognition is **not available in `af-south-1` (Cape Town)**. The closest
supported Rekognition region to South Africa is **`sa-east-1` (São Paulo)**.
The backend defaults to `sa-east-1` and the region is configurable with
`AWS_REGION`.

Only face API calls go to that region. The VPS, database, and Telegram/other
services stay where they are.

## Credentials

The VPS is not an EC2 instance, so an instance profile/role is not available.
Use a dedicated IAM user with **programmatic access keys** stored in the hermes
secret store. If the VPS later moves to EC2/ECS, switch to a role and remove the
keys.

Minimum IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rekognition:CreateCollection",
        "rekognition:DescribeCollection",
        "rekognition:IndexFaces",
        "rekognition:SearchFacesByImage",
        "rekognition:ListFaces",
        "rekognition:DeleteFaces"
      ],
      "Resource": "*"
    }
  ]
}
```

Scope the policy to the collection ARN later if your account has multiple
applications using Rekognition.

## Backend environment

```dotenv
AWS_REGION=sa-east-1
AWS_ACCESS_KEY_ID=<from secret store>
AWS_SECRET_ACCESS_KEY=<from secret store>
REKOGNITION_COLLECTION_PREFIX=yabil-timekeep
REKOGNITION_SIMILARITY_THRESHOLD=90
REKOGNITION_AMBIGUITY_MARGIN=2
```

- `REKOGNITION_COLLECTION_PREFIX` + org UUID forms the collection name, e.g.
  `yabil-timekeep-<org-uuid>`.
- `REKOGNITION_SIMILARITY_THRESHOLD` is 0–100. The owner chose **90**.
- `REKOGNITION_AMBIGUITY_MARGIN` rejects a top match when a second distinct
  employee is within this many percentage points.

The collection is created automatically on the first enrollment.

## Enrollment

1. Open the worker in the mobile admin.
2. Tap **Enroll face** / **Re-enroll face**.
3. Capture the guided samples. The app encodes each accepted frame as JPEG and
   uploads 1–5 images.
4. The backend indexes them in Rekognition and stores only `FaceId`, image ID,
   and quality metadata in `employee_faces`.
5. Re-enrollment indexes the new samples first, then removes the old faces.

Existing on-device MobileFaceNet templates **cannot be converted**. Employees
must be re-enrolled after this switch. The old `face_template` column is kept
for historical data only and is no longer used by the kiosk.

## Attendance flow

```
kiosk camera
  -> ML Kit face/quality/sharpness gate
  -> JPEG frame
  -> POST /api/v1/device/recognize (device token, rate limited)
  -> Rekognition SearchFacesByImage (threshold 90)
  -> matched employee -> attendance engine
  -> check-in/check-out result returned to kiosk
```

The client never supplies the employee ID for a face scan. If no face clears
the threshold, or the match is ambiguous, no attendance is recorded.

## Offline and fallback

Rekognition needs the network. When the face endpoint is unreachable, the kiosk
shows **Use worker code**. Code punches still use the existing offline queue and
idempotent scan ingest.

## Privacy and retention

- The app does not store raw face images. It stores Rekognition FaceIds and
  quality metadata in `employee_faces`.
- Rekognition stores its own face vectors in the collection. Delete a worker to
  clear their faces; deactivating or deleting a worker also clears them.
- Liveness is **not enabled in v1** (owner decision). A printed photo may pass
  matching if it looks like the enrolled face. Add Rekognition Face Liveness or
  the previous blink/motion check before using this for high-risk access.
- This transfers biometric data to AWS in São Paulo. Confirm POPIA/consent and
  retention requirements before production use.

## Verification

```bash
curl -fsS https://<api-host>/health
# then enroll one test worker from the mobile admin and scan them once
```

Check the backend log and the `employee_faces` table. A successful scan creates
a `scan_events` row with `confidence` equal to the Rekognition similarity / 100.
