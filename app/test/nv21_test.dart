import 'dart:typed_data';

import 'package:face_attendance/recognition/embedder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic 4x2 NV21 image: 8 luma pixels + 4 interleaved VU bytes.
Uint8List makeNv21() {
  final b = Uint8List(12);
  for (var i = 0; i < 8; i++) {
    b[i] = i * 30;
  }
  b[8] = 128; // V
  b[9] = 100; // U
  b[10] = 128; // V
  b[11] = 160; // U
  return b;
}

void main() {
  group('nv21FromPlanes', () {
    test('passes a single packed plane through untouched', () {
      final buf = makeNv21();
      final out = nv21FromPlanes([buf], [4], width: 4, height: 2);
      expect(out, equals(buf));
    });

    test('concatenates Y and VU planes (2-plane NV21)', () {
      final buf = makeNv21();
      final out = nv21FromPlanes([buf.sublist(0, 8), buf.sublist(8)], [4, 4],
          width: 4, height: 2);
      expect(out, equals(buf));
    });

    test('interleaves planar Y+U+V into VU order (3-plane)', () {
      final buf = makeNv21();
      final out = nv21FromPlanes(
        [buf.sublist(0, 8), Uint8List.fromList([100, 160]), Uint8List.fromList([128, 128])],
        [4, 2, 2],
        width: 4,
        height: 2,
      );
      expect(out, equals(buf));
    });

    test('handles Y row padding', () {
      final buf = makeNv21();
      // Two Y rows (8px each) padded to 8 bytes/row, then VU.
      final padded = Uint8List.fromList([...buf.sublist(0, 8), ...buf.sublist(4, 8)]);
      final out = nv21FromPlanes([padded, buf.sublist(8)], [8, 4],
          width: 4, height: 2);
      expect(out, equals(buf));
    });
  });

  group('nv21ToUprightBgra', () {
    test('rotation 0 keeps dims and full alpha', () {
      final r0 = nv21ToUprightBgra(makeNv21(), 4, 2, 0);
      expect(r0.width, 4);
      expect(r0.height, 2);
      expect(r0.bytes.length, 32);
      expect(r0.bytes[3], 255);
    });

    test('rotation 90 swaps dimensions', () {
      final r90 = nv21ToUprightBgra(makeNv21(), 4, 2, 90);
      expect(r90.width, 2);
      expect(r90.height, 4);
      expect(r90.bytes.length, 32);
    });

    test('mirrorX flips pixel order horizontally', () {
      final plain = nv21ToUprightBgra(makeNv21(), 4, 2, 0);
      final mirrored = nv21ToUprightBgra(makeNv21(), 4, 2, 0, mirrorX: true);
      for (var row = 0; row < 2; row++) {
        for (var c = 0; c < 4; c++) {
          for (var ch = 0; ch < 3; ch++) {
            expect(mirrored.bytes[(row * 4 + c) * 4 + ch],
                plain.bytes[(row * 4 + (3 - c)) * 4 + ch]);
          }
        }
      }
    });

    test('90° CW rotation maps pixels correctly on non-square frames', () {
      // 4x2 grayscale frame: Y rows [10,20,30,40],[50,60,70,80], neutral chroma.
      final buf = Uint8List(12);
      for (var i = 0; i < 8; i++) {
        buf[i] = 10 * (i + 1);
      }
      for (var i = 8; i < 12; i++) {
        buf[i] = 128;
      }
      final r90 = nv21ToUprightBgra(buf, 4, 2, 90);
      expect(r90.width, 2);
      expect(r90.height, 4);
      // Neutral chroma => R == G == B == Y.
      // dst(0,0) must be src top-right (Y=40): B channel at byte 0.
      expect(r90.bytes[0], 40);
      // dst(1,0) must be src bottom-right (Y=80).
      expect(r90.bytes[4], 80);
      // dst(0,1) must be src (2,0) -> Y=30.
      expect(r90.bytes[8], 30);
      // dst(1,3) must be src bottom-left (Y=50).
      expect(r90.bytes[28], 50);
    });
  });
}
