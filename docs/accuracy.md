# Accuracy calibration & evidence

_Last updated: 2026-08-19 — accuracy rework (template v2)._

## Why the kiosk mis-matched people (the v1 bug)

Users reported: (1) an enrolled person's later check-ins failed with no
clear error, (2) enrolling a second person said "face already enrolled to
another employee" even though the two people look nothing alike, and (3) a
third person checked in as that second person.

Investigation on this exact bundled model (`app/assets/models/w600k_mbf.onnx`,
InsightFace MobileFaceNet, output `[1,512]`) found the model and the
alignment math were healthy — but two real defects were degrading accuracy:

1. **Channel order was RGB; the model is trained on BGR** (OpenCV
   convention). A faithful Python replica of the app's alignment produced
   embeddings that agreed with the InsightFace reference pipeline at
   cosine 0.96–0.99 when the tensor was BGR, but only 0.87–0.95 when RGB
   (the shipped behavior). This measurably weakened separation.
2. **The accept threshold (0.38) sat inside the impostor tail.** Benchmarked
   cosine similarity on real faces:

   | condition | impostor max | impostor p95 | genuine mean |
   |---|---|---|---|
   | clean high-res photos | 0.12 | 0.10 | 0.51 |
   | 640px + NV21 4:2:0 subsampling | 0.13 | 0.10 | 0.47 |
   | 320px + NV21 | 0.16 | 0.11 | 0.41 |
   | + landmark noise up to 8px | 0.17 | 0.11 | 0.50 |

   Every condition keeps impostors far below 0.20 — yet the app accepted at
   ≥0.38. Any degraded/misaligned frame could cross 0.38 and, combined with
   the 0.06 ambiguity margin, be checked in as the nearest (wrong) employee.
   The server's same-face enrollment guard (0.6) was likewise reachable.

## Calibrated operating point (template v2)

- **Accept threshold: 0.45** — 2.6× above the worst measured impostor (0.17),
  well below the genuine mean (~0.5+).
- **Ambiguity margin: 0.10** — top-1 must beat the runner-up by at least 0.10.
- **Same-face enrollment guard (server): 0.60** unchanged.
- Thresholds live in `app/lib/config.dart` (`kAcceptThreshold`,
  `kAmbiguityMargin`) with load-bearing unit tests that fail if they are
  ever lowered below 0.45/0.10.

## Template versioning

The embedding space changed with the channel-order fix, so old templates are
not comparable to new ones. Every template now carries `template_version`
(see `docs/data-model.md`); the app ignores templates that are not the
current version and enrollment only compares against same-version templates.
**All users must re-enroll after upgrading to a build with template v2.**

## Benchmark harness

`scripts/bench/bench.py` (Python, local machine): downloads the detector
model on first run and runs the exact ONNX model through a faithful replica
of the app's alignment under simulated kiosk conditions (resolution, NV21
chroma subsampling, landmark noise), reporting genuine/impostor cosine
distributions. Place 2+ photos per person (filename `<person>-N.jpg`) in
`scripts/bench/imgs/` and run it after any model or preprocessing change to
re-calibrate the thresholds.