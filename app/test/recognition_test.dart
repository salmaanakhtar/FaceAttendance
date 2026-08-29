import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:face_attendance/recognition/embedder.dart';
import 'package:face_attendance/recognition/matcher.dart';
import 'package:face_attendance/recognition/liveness.dart';
import 'package:face_attendance/config.dart';
import 'package:face_attendance/recognition/template_store.dart';

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

    test('single employee with varied sample scores is a clear match', () {
      // Regression: a genuine scan scores high against several of the SAME
      // employee's samples. The ambiguity margin must compare DISTINCT
      // employees, otherwise this is wrongly flagged "unclear" (the bug that
      // showed "Unclear match / match 86%" for a correctly enrolled user).
      final t = vec(1);
      List<double> near(double mag, double seed) {
        var s = seed;
        final v = List<double>.generate(128, (i) {
          s = (s * 1103515245 + 12345) % 2147483647;
          return t[i] + (s / 2147483647 - 0.5) * mag;
        });
        return l2Normalize(v);
      }

      final r = matchEmbedding(t, [
        TemplateCandidate('a', near(0.5, 11)),
        TemplateCandidate('a', near(0.3, 22)),
        TemplateCandidate('a', near(0.4, 33)),
      ], acceptThreshold: 0.45, ambiguityMargin: 0.10);
      expect(r.employeeId, 'a');
      expect(r.ambiguous, isFalse);
      expect(r.matched, isTrue);
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

    test('default thresholds sit safely above the impostor tail', () {
      // Calibrated in docs/accuracy.md: impostor cosine peaks ~0.17 even
      // under heavy kiosk-like degradation. These constants are load-bearing —
      // dropping them re-opens the false-accept bug.
      expect(kAcceptThreshold, greaterThanOrEqualTo(0.45));
      expect(kAmbiguityMargin, greaterThanOrEqualTo(0.10));
    });

    test('impostor at 0.3 cosine is rejected at production defaults', () {
      final q = vec(1);
      final raw = vec(2);
      // Orthogonalize raw against q so the impostor sits at a *known* cosine.
      var dot = 0.0;
      for (var i = 0; i < 128; i++) {
        dot += raw[i] * q[i];
      }
      final r = l2Normalize(List<double>.generate(128, (i) => raw[i] - dot * q[i]));
      final impostor = l2Normalize(List<double>.generate(
          128, (i) => 0.3 * q[i] + 0.953939 * r[i])); // cosine(q, impostor) == 0.3
      final res = matchEmbedding(impostor, candidatesOf({'b': q}));
      expect(res.employeeId, isNull);
      expect(res.matched, isFalse);
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

    test('sharpness safely clamps a face box outside the frame', () {
      final bgra = Uint8List(10 * 10 * 4);
      expect(
        () => ImageSharpness.faceRegionSharpness(bgra, 10, 10, -4, -3, 20, 20),
        returnsNormally,
      );
      expect(ImageSharpness.faceRegionSharpness(bgra, 10, 10, 20, 20, 5, 5), 0);
    });

    test('enrollment guide requires front, both sides, then front', () {
      final guide = EnrollmentCaptureGuide();
      expect(guide.hint, contains('straight'));
      for (final yaw in [0.0, 2.0, -1.0]) {
        expect(guide.accept(yaw), isTrue);
      }
      expect(guide.accept(3), isFalse);
      expect(guide.hint, contains('one side'));
      expect(guide.accept(12), isTrue);
      expect(guide.accept(14), isTrue);
      expect(guide.accept(13), isFalse);
      expect(guide.hint, contains('other side'));
      expect(guide.accept(-12), isTrue);
      expect(guide.accept(-15), isTrue);
      expect(guide.accept(0), isTrue);
      expect(guide.complete, isTrue);
      expect(guide.captured, EnrollmentCaptureGuide.targetSamples);
    });
  });

  group('embedder tensor', () {
    // InsightFace models are trained on OpenCV (BGR) images. The tensor must
    // carry B,G,R in channels 0,1,2 — feeding RGB measurably degrades
    // recognition (see docs/accuracy.md).
    test('aligned tensor writes BGR channel order', () {
      const target = <Offset>[
        Offset(38.2946, 51.6963),
        Offset(73.5318, 51.5014),
        Offset(56.0252, 71.7366),
        Offset(41.5493, 92.3655),
        Offset(70.7299, 92.2041),
      ];
      final bgra = Uint8List(112 * 112 * 4); // all black
      const i = (10 * 112 + 10) * 4;
      bgra[i] = 0;       // B
      bgra[i + 1] = 128; // G
      bgra[i + 2] = 255; // R
      bgra[i + 3] = 255; // A

      // Landmarks == target -> identity transform, so output pixel (10,10)
      // samples source pixel (10,10) exactly.
      final tensor = FaceEmbedder().alignedFaceTensor(bgra, 112, 112, target);
      const idx = (10 * 112 + 10) * 3;
      expect(tensor[idx], closeTo(0 / 127.5 - 1, 1e-3));       // B -> ch0
      expect(tensor[idx + 1], closeTo(128 / 127.5 - 1, 1e-3)); // G -> ch1
      expect(tensor[idx + 2], closeTo(255 / 127.5 - 1, 1e-3)); // R -> ch2
    });
  });

  group('template version gating', () {
    test('missing version parses as stale (0) so old bundles are excluded', () {
      final t = StoredTemplate.fromJson({
        'employeeId': 'a',
        'name': 'n',
        'employeeCode': 'c',
        'embedding': [1, 0],
      });
      expect(t.templateVersion, 0);
      expect(t.templateVersion == kTemplateVersion, isFalse);
    });

    test('current version is parsed and matches the app pipeline', () {
      final t = StoredTemplate.fromJson({
        'employeeId': 'a',
        'name': 'n',
        'employeeCode': 'c',
        'templateVersion': 2,
        'embedding': [1, 0],
      });
      expect(t.templateVersion, kTemplateVersion);
    });
  });
}
