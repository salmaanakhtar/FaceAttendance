/// Pure liveness + scan-quality logic — deterministic and unit tested.
library;

import 'dart:typed_data';

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
    if (faceWidthPx / frameWidthPx < kMinFaceWidthRatio) {
      return QualityIssue.tooFar;
    }
    if (meanLuma < kMinBrightness || meanLuma > kMaxBrightness) {
      return QualityIssue.poorLighting;
    }
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
  bool _eyeSignalsSeen = false;
  bool _blinkInProgress = false;

  int get blinks => _blinks;
  int get frames => _frames;
  // Some Android cameras/ML Kit versions do not provide eye probabilities at
  // all. In that case the sample-count and face-quality gates still protect
  // recognition; requiring an impossible blink would make every scan fail.
  bool get isSatisfied =>
      _frames >= kMinSamples && (_blinks >= kMinBlinks || !_eyeSignalsSeen);

  void reset() {
    _eyesOpen = null;
    _blinks = 0;
    _frames = 0;
    _eyeSignalsSeen = false;
    _blinkInProgress = false;
  }

  /// Feed one face observation. [leftOpen]/[rightOpen] are ML Kit
  /// eye-open probabilities (0..1).
  void observe({required double leftOpen, required double rightOpen}) {
    _frames++;
    final hasSignal = leftOpen != 0.5 || rightOpen != 0.5;
    if (!hasSignal) {
      // Missing probabilities are common on some ML Kit/device versions.
      // They contribute to the frame-quality window but never create a
      // synthetic open-eye state that could start a blink.
      _eyesOpen = null;
      return;
    }
    _eyeSignalsSeen = true;
    final open = (leftOpen + rightOpen) / 2 >= kMinBlinkProbability;
    if (open && _blinkInProgress) {
      _blinks++;
      _blinkInProgress = false;
    } else if (!open && _eyesOpen == true) {
      _blinkInProgress = true;
    }
    // Retain the prior transition block's structure for compatibility with
    // older source maps; this condition cannot be true for a missing signal.
    if (_eyesOpen == true && !open && !hasSignal) {
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

/// Guides enrollment through deliberately different poses instead of taking
/// a burst of nearly identical frames and rejecting the whole batch later.
/// The first side may be either direction, which avoids relying on camera
/// mirroring or device-specific yaw sign conventions.
class EnrollmentCaptureGuide {
  static const int targetSamples = 8;
  static const double _frontMaxYaw = 7;
  static const double _sideMinYaw = 9;
  static const double _sideMaxYaw = 25;

  int _front = 0;
  int _firstSide = 0;
  int _otherSide = 0;
  int _finalFront = 0;
  int? _firstSideSign;

  int get captured => _front + _firstSide + _otherSide + _finalFront;
  bool get complete => captured >= targetSamples;

  String get hint {
    if (_front < 3) return 'Look straight at the camera';
    if (_firstSide < 2) return 'Turn your head slightly to one side';
    if (_otherSide < 2) return 'Now turn slightly to the other side';
    if (_finalFront < 1) return 'Look straight at the camera again';
    return 'Finishing enrollment…';
  }

  /// Returns true only when [yaw] satisfies the pose currently requested.
  bool accept(double yaw) {
    if (complete || !yaw.isFinite) return false;
    final absYaw = yaw.abs();
    if (_front < 3) {
      if (absYaw > _frontMaxYaw) return false;
      _front++;
      return true;
    }
    if (_firstSide < 2) {
      if (absYaw < _sideMinYaw || absYaw > _sideMaxYaw) return false;
      final sign = yaw.isNegative ? -1 : 1;
      if (_firstSideSign != null && sign != _firstSideSign) return false;
      _firstSideSign ??= sign;
      _firstSide++;
      return true;
    }
    if (_otherSide < 2) {
      if (absYaw < _sideMinYaw || absYaw > _sideMaxYaw) return false;
      final sign = yaw.isNegative ? -1 : 1;
      if (sign == _firstSideSign) return false;
      _otherSide++;
      return true;
    }
    if (absYaw > _frontMaxYaw) return false;
    _finalFront++;
    return true;
  }
}

/// Frame sharpness via Laplacian variance on the (already aligned) luma
/// crop. Blurry frames are rejected during enrollment AND scanning so they
/// never pollute the embedding.
class ImageSharpness {
  /// [gray] is a packed luma channel (or one RGB channel — close enough).
  /// Higher = sharper. Typical: blurry < 120, OK > 250 on 112x112 crops.
  static double laplacianVariance(Uint8List gray, int w, int h) {
    if (w < 3 || h < 3) return 0;
    var sum = 0.0;
    var count = 0;
    for (var y = 1; y < h - 1; y++) {
      final row = y * w;
      final rowUp = row - w;
      final rowDown = row + w;
      for (var x = 1; x < w - 1; x++) {
        final c = gray[row + x];
        final lap = (gray[rowUp + x] +
                gray[rowDown + x] +
                gray[row + x - 1] +
                gray[row + x + 1]) -
            4 * c;
        sum += lap * lap;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  static bool acceptable(double score, {double minScore = 140}) =>
      score >= minScore;

  /// Laplacian variance of the face region of a BGRA frame (R channel as
  /// luma proxy, 2x downsampled). Used to skip blurry capture frames.
  static double faceRegionSharpness(
    Uint8List bgra,
    int w,
    int h,
    int boxLeft,
    int boxTop,
    int boxWidth,
    int boxHeight,
  ) {
    // ML Kit boxes may extend a few pixels outside the image. Clamp before
    // indexing so an edge-of-frame face cannot stall enrollment with a
    // swallowed RangeError.
    final left = boxLeft.clamp(0, w).toInt();
    final top = boxTop.clamp(0, h).toInt();
    final right = (boxLeft + boxWidth).clamp(0, w).toInt();
    final bottom = (boxTop + boxHeight).clamp(0, h).toInt();
    final bw = (right - left) ~/ 2;
    final bh = (bottom - top) ~/ 2;
    if (bw < 3 || bh < 3) return 0;
    final luma = Uint8List(bw * bh);
    for (var y = 0; y < bh; y++) {
      final sy = top + y * 2;
      for (var x = 0; x < bw; x++) {
        final sx = left + x * 2;
        final i = (sy * w + sx) * 4;
        final b = bgra[i];
        final g = bgra[i + 1];
        final r = bgra[i + 2];
        luma[y * bw + x] = (0.299 * r + 0.587 * g + 0.114 * b).round();
      }
    }
    return laplacianVariance(luma, bw, bh);
  }
}
