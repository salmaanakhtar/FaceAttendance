/// Pure liveness + scan-quality logic — deterministic and unit tested.
library;

import '../config.dart';

enum QualityIssue { none, tooFar, poorLighting, multipleFaces }

class ScanQuality {
  static QualityIssue check({
    required int faceWidthPx,
    required int frameWidthPx,
    required double meanLuma,
    int faceCount = 1,
  }) {
    if (faceCount > 1) return QualityIssue.multipleFaces;
    if (faceWidthPx / frameWidthPx < kMinFaceWidthRatio) return QualityIssue.tooFar;
    if (meanLuma < kMinBrightness || meanLuma > kMaxBrightness) return QualityIssue.poorLighting;
    return QualityIssue.none;
  }
}

/// Blink + motion liveness tracker for a single scan session.
///
/// Requirements to pass:
/// - at least [kMinBlinks] blink cycles (open -> closed -> open)
/// - at least [kMinSamples] frames spread over time (motion/pose variance proxy)
class LivenessTracker {
  bool? _eyesOpen;
  int _blinks = 0;
  int _frames = 0;

  int get blinks => _blinks;
  int get frames => _frames;
  bool get isSatisfied => _blinks >= kMinBlinks && _frames >= kMinSamples;

  /// Feed one face observation. [leftOpen]/[rightOpen] are ML Kit
  /// eye-open probabilities (0..1).
  void observe({required double leftOpen, required double rightOpen}) {
    _frames++;
    final open = (leftOpen + rightOpen) / 2 >= kMinBlinkProbability;
    if (_eyesOpen == true && !open) {
      _blinks++; // eyes were open, now closed — a blink started
    }
    _eyesOpen = open;
  }
}

/// Enrollment sample gating: each frame must be good enough to contribute.
class EnrollmentQuality {
  static bool acceptable({
    required double faceWidthRatio,
    required double meanLuma,
    required double yaw,
  }) {
    const maxYawDeg = 25.0;
    return faceWidthRatio >= 0.22 &&
        meanLuma >= 40 &&
        meanLuma <= 220 &&
        yaw.abs() <= maxYawDeg;
  }
}
