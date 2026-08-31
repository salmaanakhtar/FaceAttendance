import 'package:flutter/services.dart';

const _voiceChannel = MethodChannel('faceattendance/voice');

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

  /// Speaks the employee-specific result without blocking scan state reset.
  static Future<void> speak(String text) async {
    try {
      await _voiceChannel.invokeMethod<void>('speak', {'text': text});
    } catch (_) {
      // Voice is an enhancement; sound/haptics still confirm the scan.
    }
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
