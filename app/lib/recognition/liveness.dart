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
        final lap = (gray[rowUp + x] + gray[rowDown + x] + gray[row + x - 1] + gray[row + x + 1]) - 4 * c;
        sum += lap * lap;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  static bool acceptable(double score, {double minScore = 140}) => score >= minScore;

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
    final bw = boxWidth ~/ 2;
    final bh = boxHeight ~/ 2;
    if (bw < 3 || bh < 3) return 0;
    final luma = Uint8List(bw * bh);
    for (var y = 0; y < bh; y++) {
      final sy = boxTop + y * 2;
      for (var x = 0; x < bw; x++) {
        final sx = boxLeft + x * 2;
        luma[y * bw + x] = bgra[(sy * w + sx) * 4 + 2];
      }
    }
    return laplacianVariance(luma, bw, bh);
  }
}
