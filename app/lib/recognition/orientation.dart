/// Frame orientation candidates for the adaptive probe.
/// Front/back sensors are mounted differently per device, so instead of
/// assuming a formula we probe a small set of rotation+mirror combos on the
/// live frame and lock the first one where ML Kit finds a face.
library;

class FrameOrientation {
  final int rotationDeg;
  final bool mirrorX;
  const FrameOrientation(this.rotationDeg, this.mirrorX);

  @override
  String toString() => 'rot:$rotationDeg mirror:$mirrorX';
}

/// Candidates ordered by likelihood: the classic back-camera formula,
/// the classic front-camera formula (rotate + mirror), then the same with
/// the complementary rotation, then plain landscape.
List<FrameOrientation> orientationCandidates(int sensorOrientation) {
  final s = sensorOrientation % 360;
  return [
    FrameOrientation(s, false),
    FrameOrientation(s, true),
    FrameOrientation((360 - s) % 360, false),
    FrameOrientation((360 - s) % 360, true),
    const FrameOrientation(0, false),
    const FrameOrientation(90, false),
  ];
}
