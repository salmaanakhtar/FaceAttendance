import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../config.dart';
import 'matcher.dart';

/// Face embedding via InsightFace MobileFaceNet (ONNX, on-device).
/// Pipeline: YUV frame -> upright RGBA -> 5-point similarity alignment
/// to canonical 112x112 -> NCHW float [-1,1] -> 512-d embedding.
class FaceEmbedder {
  OrtSession? _session;
  bool _ready = false;
  String? _error;

  bool get ready => _ready;
  String? get error => _error;

  Future<void> init() async {
    try {
      OrtEnv.instance.init(level: OrtLoggingLevel.error);
      final options = OrtSessionOptions()..setIntraOpNumThreads(2);
      final bytes = await rootBundle.load(kModelAsset);
      _session = OrtSession.fromBuffer(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), options);
      _ready = true;
    } catch (e) {
      _error = 'model init failed: $e';
    }
  }

  /// Encode a face crop (upright RGBA frame + 5 landmarks) into an embedding.
  /// Returns null on failure.
  List<double>? embed({
    required Uint8List rgba,
    required int width,
    required int height,
    required List<Offset> landmarks, // 5: lEye, rEye, nose, lMouth, rMouth
  }) {
    final session = _session;
    if (session == null) return null;
    final input = alignedFaceTensor(rgba, width, height, landmarks);
    final runOptions = OrtRunOptions();
    final inputValue = OrtValueTensor.createTensorWithDataList(
      input,
      [1, 3, 112, 112],
    );
    final outputs = session.run(runOptions, {'input.1': inputValue});
    inputValue.release();
    runOptions.release();
    final out = outputs.first;
    if (out == null) return null;
    final value = out.value as dynamic;
    out.release();
    if (value is! List) return null;
    final flat = <double>[];
    for (final v in value) {
      if (v is List) {
        flat.addAll(v.cast<double>());
      } else {
        flat.add((v as num).toDouble());
      }
    }
    if (flat.length < 128) return null;
    return l2Normalize(flat);
  }

  /// Warp the face region to the canonical 112x112 grid using the
  /// InsightFace 5-point alignment. Input buffer is BGRA8888 (upright).
  /// Output: NCHW float32 in [-1,1].
  Float32List alignedFaceTensor(
    Uint8List rgba,
    int width,
    int height,
    List<Offset> landmarks,
  ) {
    const target = <Offset>[
      Offset(38.2946, 51.6963),
      Offset(73.5318, 51.5014),
      Offset(56.0252, 71.7366),
      Offset(41.5493, 92.3655),
      Offset(70.7299, 92.2041),
    ];
    // Umeyama similarity transform (scale, rotation, translation) src -> dst.
    final t = _similarityTransform(landmarks, target);
    final out = Float32List(112 * 112 * 3);
    final inv = _invert(t);
    var idx = 0;
    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 112; x++) {
        final sx = inv[0] * x + inv[1] * y + inv[4];
        final sy = inv[2] * x + inv[3] * y + inv[5];
        // BGRA layout: [B, G, R, A]
        final b = _bilinearAt(rgba, width, height, sx, sy, 0);
        final g = _bilinearAt(rgba, width, height, sx, sy, 1);
        final r = _bilinearAt(rgba, width, height, sx, sy, 2);
        // ArcFace normalization: (v / 255 - 0.5) / 0.5  ==  v/127.5 - 1
        out[idx++] = r / 127.5 - 1.0;
        out[idx++] = g / 127.5 - 1.0;
        out[idx++] = b / 127.5 - 1.0;
      }
    }
    return out;
  }
}

/// Similarity transform [a b tx; c d ty] (2x3) mapping src -> dst.
/// Closed-form least squares (Umeyama).
List<double> _similarityTransform(List<Offset> src, List<Offset> dst) {
  final n = src.length;
  var sx = 0.0, sy = 0.0, dx = 0.0, dy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += src[i].dx;
    sy += src[i].dy;
    dx += dst[i].dx;
    dy += dst[i].dy;
  }
  sx /= n;
  sy /= n;
  dx /= n;
  dy /= n;
  var d1 = 0.0, d2 = 0.0, d3 = 0.0, d4 = 0.0;
  for (var i = 0; i < n; i++) {
    final x = src[i].dx - sx;
    final y = src[i].dy - sy;
    final u = dst[i].dx - dx;
    final v = dst[i].dy - dy;
    d1 += x * u + y * v;
    d2 += x * v - y * u;
    d3 += x * x + y * y;
    d4 += u * u + v * v;
  }
  final scale = math.sqrt(d4 / d3);
  final theta = math.atan2(d2, d1);
  final c = scale * math.cos(theta);
  final s = scale * math.sin(theta);
  return [c, -s, s, c, dx - c * sx + s * sy, dy - s * sx - c * sy];
}

List<double> _invert(List<double> m) {
  final det = m[0] * m[3] - m[1] * m[2];
  final invDet = 1 / det;
  return [
    m[3] * invDet,
    -m[1] * invDet,
    -m[2] * invDet,
    m[0] * invDet,
    -(m[3] * m[4] - m[1] * m[5]) * invDet,
    -(-m[2] * m[4] + m[0] * m[5]) * invDet,
  ];
}

/// Bilinear sample of channel [channel] (0=B,1=G,2=R in BGRA layout).
double _bilinearAt(Uint8List bgra, int w, int h, double fx, double fy, int channel) {
  if (fx < 0 || fx > w - 1 || fy < 0 || fy > h - 1) return 0;
  final x0 = fx.floor();
  final y0 = fy.floor();
  final x1 = math.min(x0 + 1, w - 1);
  final y1 = math.min(y0 + 1, h - 1);
  final wx = fx - x0;
  final wy = fy - y0;
  final i00 = (y0 * w + x0) * 4 + channel;
  final i10 = (y0 * w + x1) * 4 + channel;
  final i01 = (y1 * w + x0) * 4 + channel;
  final i11 = (y1 * w + x1) * 4 + channel;
  final v00 = bgra[i00];
  final v10 = bgra[i10];
  final v01 = bgra[i01];
  final v11 = bgra[i11];
  final top = v00 + (v10 - v00) * wx;
  final bottom = v01 + (v11 - v01) * wx;
  return top + (bottom - top) * wy;
}

/// YUV420 (NV21 2-plane or YUV_420_888 3-plane) -> upright BGRA bytes.
/// The image is rotated by [rotationDeg] (90/180/270/0) so the output is
/// always upright; [mirrorX] mirrors horizontally in the upright space.
/// Returns (bytes, width, height).
({Uint8List bytes, int width, int height}) yuvToUprightRgba(
  CameraImage image,
  int rotationDeg, {
  bool mirrorX = false,
}) {
  final yPlane = image.planes.first;
  final width = image.width;
  final height = image.height;
  final nv21 = image.planes.length == 2;

  int uAt(int x, int y) {
    final row = (y >> 1);
    final col = (x >> 1);
    if (nv21) {
      // NV21: plane 1 is interleaved V,U — U at odd offsets.
      return image.planes[1].bytes[image.planes[1].bytesPerRow * row + (col << 1) + 1];
    }
    return image.planes[1].bytes[image.planes[1].bytesPerRow * row + col];
  }

  int vAt(int x, int y) {
    final row = (y >> 1);
    final col = (x >> 1);
    if (nv21) {
      // V at even offsets.
      return image.planes[1].bytes[image.planes[1].bytesPerRow * row + (col << 1)];
    }
    return image.planes[2].bytes[image.planes[2].bytesPerRow * row + col];
  }

  int yAt(int x, int y) {
    return yPlane.bytes[yPlane.bytesPerRow * y + x];
  }

  // Determine output dims and source mapping for the rotation.
  final swapped = (rotationDeg % 180) != 0;
  final outW = swapped ? height : width;
  final outH = swapped ? width : height;
  final out = Uint8List(outW * outH * 4);

  for (var oy = 0; oy < outH; oy++) {
    for (var ox = 0; ox < outW; ox++) {
      // Mirror in the final upright space for front cameras.
      final outX = mirrorX ? outW - 1 - ox : ox;
      int sx;
      int sy;
      switch (rotationDeg % 360) {
        case 90:
          sx = height - 1 - oy;
          sy = ox;
        case 270:
          sx = oy;
          sy = width - 1 - ox;
        case 180:
          sx = width - 1 - ox;
          sy = height - 1 - oy;
        default:
          sx = ox;
          sy = oy;
      }
      final yv = yAt(sx, sy);
      final uv = uAt(sx, sy) - 128;
      final vv = vAt(sx, sy) - 128;
      final r = (yv + 1.402 * vv).round().clamp(0, 255);
      final g = (yv - 0.344136 * uv - 0.714136 * vv).round().clamp(0, 255);
      final b = (yv + 1.772 * uv).round().clamp(0, 255);
      final idx = (oy * outW + outX) * 4;
      out[idx] = b;
      out[idx + 1] = g;
      out[idx + 2] = r;
      out[idx + 3] = 255;
    }
  }
  return (bytes: out, width: outW, height: outH);
}
