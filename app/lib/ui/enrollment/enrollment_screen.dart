import 'dart:async';
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../admin/admin_api.dart';
import '../../../config.dart';
import '../../../recognition/embedder.dart';
import '../../../recognition/liveness.dart';
import '../../../recognition/matcher.dart';
import '../../../recognition/template_store.dart';
import '../../../util/feedback.dart';

enum _CaptureState { ready, busy, done, error }

/// Guided face enrollment: captures quality-gated samples with pose
/// variety, fuses them into one embedding, and submits to the server.
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  CameraController? _camera;
  FaceDetector? _detector;
  FaceEmbedder? _embedder;
  bool _busy = false;
  _CaptureState _state = _CaptureState.ready;
  String? _error;
  final List<List<double>> _samples = [];
  final List<double> _yaws = [];
  int _captured = 0;
  String _hint = 'Center your face in the frame';
  int _rejected = 0;

  static const _targetSamples = 8;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _embedder = FaceEmbedder();
      await _embedder!.init();
      _detector = FaceDetector(
        options: FaceDetectorOptions(enableLandmarks: true, enableClassification: true),
      );
      final cameras = await availableCameras();
      final ordered = [
        ...cameras.where((c) => c.lensDirection == CameraLensDirection.front),
        ...cameras.where((c) => c.lensDirection != CameraLensDirection.front),
      ];
      for (final candidate in ordered) {
        final c = CameraController(candidate, kCameraResolution,
            enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
        try {
          await c.initialize();
          _camera = c;
          c.startImageStream(_onFrame);
          if (mounted) setState(() {});
          return;
        } catch (_) {
          await c.dispose();
        }
      }
      setState(() {
        _state = _CaptureState.error;
        _error = 'No usable camera';
      });
    } catch (e) {
      setState(() {
        _state = _CaptureState.error;
        _error = 'Init failed: $e';
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _captured >= _targetSamples || _state != _CaptureState.ready) return;
    final detector = _detector;
    final embedder = _embedder;
    final camera = _camera;
    if (detector == null || embedder == null || camera == null) return;
    _busy = true;
    try {
      final rotation = camera.description.sensorOrientation % 360;
      final upright = yuvToUprightRgba(image, rotation);
      final inputImage = InputImage.fromBytes(
        bytes: upright.bytes,
        metadata: InputImageMetadata(
          size: Size(upright.width.toDouble(), upright.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: upright.width * 4,
        ),
      );
      final faces = await detector.processImage(inputImage);
      if (faces.isEmpty) {
        _setHint('Center your face in the frame');
        return;
      }
      if (faces.length > 1) {
        _setHint('Only one person in frame');
        return;
      }
      final face = faces.first;
      final ratio = face.boundingBox.width / upright.width;
      final luma = _meanLuma(upright.bytes, upright.width, upright.height);
      final yaw = face.headEulerAngleY ?? 0;
      if (!EnrollmentQuality.acceptable(faceWidthRatio: ratio, meanLuma: luma, yaw: yaw)) {
        _rejected++;
        if (ratio < 0.22) {
          _setHint('Move closer');
        } else if (luma < 40) {
          _setHint('Better lighting needed');
        } else {
          _setHint('Face the camera directly');
        }
        return;
      }
      final landmarks = _landmarks(face);
      if (landmarks == null) return;
      final emb = embedder.embed(
          rgba: upright.bytes,
          width: upright.width,
          height: upright.height,
          landmarks: landmarks);
      if (emb == null) return;
      _samples.add(emb);
      _yaws.add(yaw);
      _captured++;
      await FeedbackFx.scanCapture();
      if (mounted) setState(() {});
      if (_captured >= _targetSamples) {
        await _finish();
      } else {
        _setHint('Keep still — $_captured/$_targetSamples');
      }
    } catch (_) {
      // transient frame error — keep scanning
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish() async {
    // Pose variety guard: if the face barely moved, ask for one more pass.
    final yawSpread = _yaws.isEmpty
        ? 0.0
        : _yaws.reduce((a, b) => a > b ? a : b) - _yaws.reduce((a, b) => a < b ? a : b);
    if (yawSpread < 6.0) {
      _samples.clear();
      _yaws.clear();
      _captured = 0;
      _setHint('Turn your head slightly left and right');
      return;
    }
    setState(() => _state = _CaptureState.busy);
    final fused = fuseEmbeddings(_samples);
    final quality = {
      'samples': _samples.length,
      'model': 'w600k_mbf',
      'yawSpreadDeg': yawSpread.round(),
      'rejectedFrames': _rejected,
    };
    try {
      await AdminApi.instance.enrollEmployee(widget.employeeId,
          embedding: fused, quality: quality);
      // Push the new template to this kiosk immediately.
      try {
        await TemplateStore.instance.syncFromServer();
      } catch (_) {}
      if (mounted) {
        setState(() => _state = _CaptureState.done);
      }
      await FeedbackFx.success();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _CaptureState.error;
          _error = 'Enrollment failed: $e';
        });
      }
    }
  }

  List<Offset>? _landmarks(Face face) {
    final lm = face.landmarks;
    if (lm.isEmpty) return null;
    Point<int>? get(FaceLandmarkType t) => lm[t]?.position;
    final lEye = get(FaceLandmarkType.leftEye);
    final rEye = get(FaceLandmarkType.rightEye);
    final nose = get(FaceLandmarkType.noseBase);
    final lMouth = get(FaceLandmarkType.leftMouth);
    final rMouth = get(FaceLandmarkType.rightMouth);
    if (lEye == null || rEye == null || nose == null || lMouth == null || rMouth == null) {
      return null;
    }
    return [
      Offset(lEye.x.toDouble(), lEye.y.toDouble()),
      Offset(rEye.x.toDouble(), rEye.y.toDouble()),
      Offset(nose.x.toDouble(), nose.y.toDouble()),
      Offset(lMouth.x.toDouble(), lMouth.y.toDouble()),
      Offset(rMouth.x.toDouble(), rMouth.y.toDouble()),
    ];
  }

  double _meanLuma(Uint8List bgra, int w, int h) {
    const step = 16;
    var sum = 0.0;
    var n = 0;
    for (var y = 0; y < h; y += step) {
      for (var x = 0; x < w; x += step) {
        sum += bgra[(y * w + x) * 4 + 2];
        n++;
      }
    }
    return n == 0 ? 128 : sum / n;
  }

  void _setHint(String hint) {
    if (mounted && _hint != hint) setState(() => _hint = hint);
  }

  @override
  void dispose() {
    _camera?.stopImageStream();
    _camera?.dispose();
    _detector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        title: const Text('Enroll face'),
        automaticallyImplyLeading: _state != _CaptureState.busy,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_camera != null && _camera!.value.isInitialized)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              child: CameraPreview(_camera!),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white24)),
          if (_state == _CaptureState.done)
            _overlay(const Icon(Icons.check_circle_rounded, color: Color(0xFF2FBF71), size: 64),
                'Face enrolled', 'You can now check in with this face.')
          else if (_state == _CaptureState.error)
            _overlay(const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5D5D), size: 64),
                'Enrollment failed', _error ?? 'Please try again.')
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE60B0D10)],
                    stops: [0.0, 0.6],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _targetSamples; i++)
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _captured ? const Color(0xFF2FBF71) : Colors.white24,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overlay(Widget icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_state == _CaptureState.done),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2F6BFF),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_state == _CaptureState.done ? 'Done' : 'Try again',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
