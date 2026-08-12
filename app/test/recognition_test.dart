import 'dart:typed_data';

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

List<TemplateCandidate> candidatesOf(Map<String, List<double>> t) =>
    [for (final e in t.entries) TemplateCandidate(e.key, e.value)];

void main() {
  group('matcher', () {
    test('matches the right template with high score', () {
      final t = vec(1);
      final templates = {'a': t, 'b': vec(2), 'c': vec(3)};
      final r = matchEmbedding(t, candidatesOf(templates), acceptThreshold: 0.5);
      expect(r.employeeId, 'a');
      expect(r.score, greaterThan(0.99));
      expect(r.ambiguous, isFalse);
    });

    test('unknown face (far from everyone) is rejected', () {
      final templates = {'a': vec(1), 'b': vec(2)};
      final query = vec(99);
      final r = matchEmbedding(query, candidatesOf(templates), acceptThreshold: 0.5);
      expect(r.employeeId, isNull);
      expect(r.matched, isFalse);
    });

    test('ambiguous when two templates are near-identical', () {
      final t = vec(1);
      final templates = {'a': t, 'b': vec(1)};
      final r = matchEmbedding(t, candidatesOf(templates), acceptThreshold: 0.5, ambiguityMargin: 0.1);
      expect(r.ambiguous, isTrue);
      expect(r.matched, isFalse);
    });

    test('sample candidates boost a weak fused template', () {
      final strong = vec(1);
      final noise = vec(7);
      final weakFused = l2Normalize(List<double>.generate(128, (i) => strong[i] * 0.6 + noise[i] * 0.4));
      final other = vec(2);
      // Fused template alone would fail the threshold…
      final solo = matchEmbedding(strong, candidatesOf({'a': weakFused, 'b': other}),
          acceptThreshold: 0.9);
      expect(solo.matched, isFalse);
      // …but the employee's enrollment sample matches.
      final withSamples = matchEmbedding(strong, [
        TemplateCandidate('a', weakFused),
        TemplateCandidate('a', strong),
        TemplateCandidate('b', other),
      ], acceptThreshold: 0.9);
      expect(withSamples.employeeId, 'a');
      expect(withSamples.matched, isTrue);
    });

    test('second-best score ignores other candidates of the same employee', () {
      final t = vec(1);
      final r = matchEmbedding(t, [
        TemplateCandidate('a', t),
        TemplateCandidate('a', t), // same employee — must not become the margin rival
        TemplateCandidate('b', vec(2)),
      ], acceptThreshold: 0.5, ambiguityMargin: 0.1);
      expect(r.employeeId, 'a');
      expect(r.ambiguous, isFalse);
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

    test('robust fuse drops outlier samples', () {
      final good = vec(1);
      final outlier = l2Normalize(List<double>.generate(128, (i) => -good[i]));
      final fused = robustFuse([good, good, good, outlier]);
      // With the outlier removed, the fused vector should match good closely.
      expect(cosineSimilarity(fused, good), greaterThan(0.9));
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

    test('sharpness: flat image is blurry, edges are sharp', () {
      final flat = Uint8List(64); // all zeros — no edges
      expect(ImageSharpness.laplacianVariance(flat, 8, 8), 0);

      // Vertical edge in the middle of an 8x8 image.
      final edge = Uint8List(64);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          edge[y * 8 + x] = x < 4 ? 0 : 255;
        }
      }
      expect(ImageSharpness.laplacianVariance(edge, 8, 8), greaterThan(0));
      expect(ImageSharpness.acceptable(ImageSharpness.laplacianVariance(edge, 8, 8),
              minScore: 100),
          isTrue);
    });
  });
}
