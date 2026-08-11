import 'package:flutter_test/flutter_test.dart';
import 'package:face_attendance/recognition/matcher.dart';
import 'package:face_attendance/recognition/liveness.dart';

List<double> vec(double seed) {
  var s = seed;
  final v = List<double>.generate(128, (_) {
    s = (s * 1103515245 + 12345) % 2147483647;
    return (s / 2147483647) * 2 - 1;
  });
  return l2Normalize(v);
}

void main() {
  group('matcher', () {
    test('matches the right template with high score', () {
      final t = vec(1);
      final templates = {'a': t, 'b': vec(2), 'c': vec(3)};
      final r = matchEmbedding(t, templates, acceptThreshold: 0.5);
      expect(r.employeeId, 'a');
      expect(r.score, greaterThan(0.99));
      expect(r.ambiguous, isFalse);
    });

    test('unknown face (far from everyone) is rejected', () {
      final templates = {'a': vec(1), 'b': vec(2)};
      final query = vec(99);
      final r = matchEmbedding(query, templates, acceptThreshold: 0.5);
      expect(r.employeeId, isNull);
      expect(r.matched, isFalse);
    });

    test('ambiguous when two templates are near-identical', () {
      final t = vec(1);
      final templates = {'a': t, 'b': vec(1)};
      final r = matchEmbedding(t, templates, acceptThreshold: 0.5, ambiguityMargin: 0.1);
      expect(r.ambiguous, isTrue);
      expect(r.matched, isFalse);
    });

    test('fuse averages and normalizes', () {
      final fused = fuseEmbeddings([vec(1), vec(1), vec(1)]);
      expect(fused.length, 128);
      var norm = 0.0;
      for (final x in fused) {
        norm += x * x;
      }
      expect(norm, closeTo(1.0, 1e-9));
    });

    test('action hint alternates and falls back to in', () {
      expect(hintDirection(lastDirection: null, isCurrentlyIn: null), 'in');
      expect(hintDirection(lastDirection: 'in', isCurrentlyIn: null), 'out');
      expect(hintDirection(lastDirection: 'out', isCurrentlyIn: null), 'in');
      expect(hintDirection(lastDirection: 'in', isCurrentlyIn: true), 'out');
      expect(hintDirection(lastDirection: null, isCurrentlyIn: false), 'in');
    });
  });

  group('liveness', () {
    test('requires at least one blink and enough frames', () {
      final t = LivenessTracker();
      t.observe(leftOpen: 0.9, rightOpen: 0.9);
      t.observe(leftOpen: 0.1, rightOpen: 0.1); // blink
      t.observe(leftOpen: 0.9, rightOpen: 0.9);
      expect(t.blinks, 1);
      expect(t.frames, 3);
      expect(t.isSatisfied, isFalse); // not enough frames yet

      t.observe(leftOpen: 0.9, rightOpen: 0.9);
      expect(t.isSatisfied, isTrue);
    });

    test('sustained closed eyes do not count as a blink', () {
      final t = LivenessTracker();
      t.observe(leftOpen: 0.9, rightOpen: 0.9);
      t.observe(leftOpen: 0.1, rightOpen: 0.1);
      t.observe(leftOpen: 0.1, rightOpen: 0.1); // still closed — no new blink
      expect(t.blinks, 1);
    });

    test('quality: too far, poor light, multiple faces', () {
      expect(ScanQuality.check(faceWidthPx: 30, frameWidthPx: 640, meanLuma: 120), QualityIssue.tooFar);
      expect(ScanQuality.check(faceWidthPx: 200, frameWidthPx: 640, meanLuma: 5), QualityIssue.poorLighting);
      expect(ScanQuality.check(faceWidthPx: 200, frameWidthPx: 640, meanLuma: 120, faceCount: 2),
          QualityIssue.multipleFaces);
      expect(ScanQuality.check(faceWidthPx: 200, frameWidthPx: 640, meanLuma: 120), QualityIssue.none);
    });
  });
}
