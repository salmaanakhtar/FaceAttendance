# Biometrics / face recognition approach

## Legacy biometric architecture

The kiosk no longer uses face recognition for attendance. Worker punches are
entered by employee code and processed by the same server attendance engine.
The following remains as legacy enrollment/template documentation for existing
records and any future optional biometric mode; it is not part of the active
kiosk check-in flow.

1. **Detection** — Google ML Kit face detection (on-device) on camera frames:
   face box, landmarks, probabilities (eyes open, smile), head Euler angles.
2. **Embedding** — MobileFaceNet (TFLite, 128-d) runs on-device via
   `tflite_flutter`. The model is bundled in the APK assets (~4 MB).
3. **Matching** — cosine similarity against the local template store. Threshold
   tuned per accuracy doc; top-1 candidate must beat the acceptance threshold
   AND clear margin over the runner-up (ambiguity guard). A near-match that is
   too close to two different templates is treated as **ambiguous**, never
   auto-accepted.
4. **Templates** — on enrollment, N quality-gated samples (pose variation,
   brightness, sharpness) are fused into one embedding stored server-side
   encrypted (AES-256-GCM, per-org key) and pushed to enrolled kiosk devices
   encrypted at rest (Flutter secure storage / encrypted Hive). Raw face images
   are never persisted — only quality metadata.

## Liveness (unattended kiosk)

- **Blink challenge**: the scan session requires at least one natural
  eye-blink within the window (ML Kit eye-open probabilities), which defeats
  static photo replay.
- **Motion + geometry checks**: inter-frame bounding-box stability, head pose
  variance, and a minimum frame span across samples — defeats frozen videos.
- Score is recorded per scan event (`liveness_score`) and logged; repeated
  failures rate-limit retries per device.
- Documented limitation: 2D-liveness (no depth sensor). On devices with a
  ToF/depth camera this can be upgraded without API changes.

## Enrollment quality gates (fail the enrollment, don't ship a bad template)

- Minimum N samples with pose spread (yaw/pitch within range, varied)
- Capture is staged (front, one side, opposite side, front) with spacing between
  accepted frames, so a burst of identical frames cannot cause an endless
  reject-and-restart loop.
- Sharpness and brightness floors per sample
- Reject if the fused embedding is within a "same-face" distance of any
  existing employee's template but the claimed identity differs (prevents
  enrolling the same face twice under different names)
- Enrollment UI must pass every gate; poor data cannot silently produce a
  template.
- Deactivating an employee clears their biometric template. Reactivation
  requires a fresh enrollment, preventing inactive records from blocking a new
  employee while preserving the audit trail.
- Face regions are clamped to image bounds before sharpness analysis because
  detectors may return boxes that extend slightly beyond the camera frame.

## Accuracy measurements

Benchmarks (threshold tuning, FAR/FRR, margin distribution, ambiguity rates)
live in `docs/` as `accuracy.md` once the pipeline is running; the same
harness is used by the gauntlet critic. See `docs/limitations.md` for
operating limits (glasses, masks, aging, extreme angles, lighting).
