import 'package:flutter/services.dart';

/// Deliberate, minimal audio/haptic feedback for scan outcomes.
class FeedbackFx {
  static Future<void> scanCapture() async {
    await SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  static Future<void> success() async {
    await SystemSound.play(SystemSoundType.click);
    HapticFeedback.heavyImpact();
  }

  static Future<void> error() async {
    await SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
  }

  static Future<void> adminUnlock() async {
    await SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }
}
