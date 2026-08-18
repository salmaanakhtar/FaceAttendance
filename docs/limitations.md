# Known limitations

Updated as discovered. Honest list; see docs/gauntlet-findings.md for the
iteration loop.

- **2D liveness only** (no depth sensor): blink + motion checks defeat photo/
  frozen-video replay; a high-quality real-time video replay of a co-worker
  could in principle spoof. Mitigated by liveness score logging, rate limits,
  and kiosk placement. Depth-camera upgrade path documented.
- **Re-enrollment required after pipeline changes**: any change to the
  embedding pipeline (model, preprocessing, channel order) bumps
  `templateVersion`; older templates are ignored by the matcher and must be
  re-enrolled (see docs/accuracy.md).
- **Lighting sensitivity**: recognition degrades in very low/high light;
  enrollment gates require good lighting so templates are reliable.
- **First-scan latency**: on slow devices the first frame analysis can take
  ~1–2 s; subsequent frames are much faster (warm-up).
- **Template size** per employee is small (128 floats), so even thousands of
  employees match in milliseconds on-device; org template sync is delta-based.
- **Offline corrections**: manual corrections require connectivity (admin
  actions are server-authoritative); offline queue covers scan events only.
- **Face-obscuring PPE / masks**: documented false-rejection behavior; masks
  degrade recognition — flagged in UI as "face not fully visible" guidance.
