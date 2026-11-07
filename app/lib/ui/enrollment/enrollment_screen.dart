import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../../admin/admin_api.dart';
import '../../../config.dart';
import '../../../recognition/embedder.dart';
import '../../../recognition/liveness.dart';
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
  bool _busy = false;
  _CaptureState _state = _CaptureState.ready;
  String? _error;
  final List<Uint8List> _images = [];
  final EnrollmentCaptureGuide _guide = EnrollmentCaptureGuide();
  DateTime? _lastCaptureAt;
  int _captured = 0;
  String _hint = 'Center your face in the frame';
  int _rejected = 0;
  int _frame = 0;
  String _diag = '';

  static const _captureSpacing = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: true,
          enableClassification: true,
        ),
      );
      final cameras = await availableCameras();
      final ordered = [
        ...cameras.where((c) => c.lensDirection == CameraLensDirection.front),
        ...cameras.where((c) => c.lensDirection != CameraLensDirection.front),
      ];
      for (final candidate in ordered) {
        final c = CameraController(candidate, kCameraResolution,
            enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
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
    if (_busy || _guide.complete || _state != _CaptureState.ready) return;
    final detector = _detector;
    final camera = _camera;
    if (detector == null || camera == null) return;
    _busy = true;
    try {
      final camera = _camera!;
      final rotationDeg = camera.description.sensorOrientation % 360;

      // Detection: raw NV21 buffer + rotation metadata (the supported path).
      final inputImage = InputImage.fromBytes(
        bytes: nv21Of(image),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.values[rotationDeg ~/ 90],
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
      final faces = await detector.processImage(inputImage).timeout(
            const Duration(seconds: 4),
          );
      _frame++;

      // Embedding crop: same rotation as ML Kit (raw sensor buffer is
      // unmirrored, so upright coordinate spaces match exactly).
      final upright = yuvToUprightRgba(image, rotationDeg, mirrorX: false);
      if (faces.isEmpty) {
        _setHint('Center your face in the frame');
        _updateDiag(faces: 0, landmarks: 0);
        return;
      }
      if (faces.length > 1) {
        _setHint('Only one person in frame');
        _updateDiag(faces: faces.length, landmarks: faces.first.landmarks.length);
        return;
      }
      final face = faces.first;
      if (_frame % 20 == 0) {
        // ignore: avoid_print
        print('[enroll] face box=${face.boundingBox} landmarks=${face.landmarks.length} '
            'yaw=${face.headEulerAngleY?.toStringAsFixed(1)}');
      }
      final ratio = face.boundingBox.width / upright.width;
      final luma = _meanLuma(upright.bytes, upright.width, upright.height);
      final yaw = face.headEulerAngleY ?? 0;
      _updateDiag(
          faces: faces.length,
          landmarks: face.landmarks.length,
          ratio: ratio,
          luma: luma.round(),
          yaw: yaw);
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
      // Sharpness gate: skip motion-blurred frames so they never pollute
      // the enrollment samples.
      final sharpness = ImageSharpness.faceRegionSharpness(
        upright.bytes, upright.width, upright.height,
        face.boundingBox.left.round(), face.boundingBox.top.round(),
        face.boundingBox.width.round(), face.boundingBox.height.round(),
      );
      if (!ImageSharpness.acceptable(sharpness)) {
        _rejected++;
        _setHint('Hold still — capturing a sharp frame');
        return;
      }
      final now = DateTime.now();
      if (_lastCaptureAt != null && now.difference(_lastCaptureAt!) < _captureSpacing) {
        return;
      }
      final bitmap = img.Image.fromBytes(
        width: upright.width,
        height: upright.height,
        bytes: upright.bytes.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      final jpeg = img.encodeJpg(bitmap, quality: 85);
      if (jpeg.length > 2 * 1024 * 1024) {
        _setHint('Image is too large — move back slightly');
        return;
      }
      if (!_guide.accept(yaw)) {
        _setHint(_guide.hint);
        return;
      }
      _images.add(jpeg);
      _lastCaptureAt = now;
      _captured = _guide.captured;
      await FeedbackFx.scanCapture();
      if (mounted) setState(() {});
      if (_guide.complete) {
        await _finish();
      } else {
        _setHint(_guide.hint);
      }
    } catch (e) {
      _frame++;
      // Never swallow silently: surface the failure on screen so it is
      // diagnosable without a PC.
      // ignore: avoid_print
      print('[enroll] frame error: $e');
      if (_frame % 5 == 0) {
        final msg = e.toString();
        _setDiagOnly('err: ${msg.length > 140 ? msg.substring(0, 140) : msg}');
      }
    } finally {
      _busy = false;
    }
  }

  void _setDiagOnly(String text) {
    if (mounted && _diag != text) setState(() => _diag = text);
  }

  String _syncResult = '';

  Future<void> _finish() async {
    setState(() => _state = _CaptureState.busy);
    try {
      await AdminApi.instance.enrollFaceImages(widget.employeeId, _images);
      _syncResult =
          '${_images.length} face samples enrolled in AWS Rekognition';
      if (mounted) {
        setState(() => _state = _CaptureState.done);
      }
      await FeedbackFx.success();
    } on DioException catch (e) {
      String? serverMessage;
      final responseData = e.response?.data;
      if (responseData is Map) {
        final error = responseData['error'];
        if (error is Map && error['message'] is String) {
          serverMessage = error['message'] as String;
        }
      }
      final status = e.response?.statusCode;
      final message = status == 409
          ? (serverMessage ?? 'This face is already enrolled to another active employee. '
              'Open that employee and use Re-enroll, or deactivate the obsolete record first.')
          : serverMessage != null
              ? 'Enrollment failed: $serverMessage'
              : 'Enrollment failed (${status ?? 'network'}): $e';
      if (mounted) {
        setState(() {
          _state = _CaptureState.error;
          _error = message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _CaptureState.error;
          _error = 'Enrollment failed: $e';
        });
      }
    }
  }

  double _meanLuma(Uint8List bgra, int w, int h) {
    // True BT.601 luma (the old code read only the red channel).
    const step = 16;
    var sum = 0.0;
    var n = 0;
    for (var y = 0; y < h; y += step) {
      for (var x = 0; x < w; x += step) {
        final i = (y * w + x) * 4;
        final b = bgra[i].toDouble();
        final g = bgra[i + 1].toDouble();
        final r = bgra[i + 2].toDouble();
        sum += 0.299 * r + 0.587 * g + 0.114 * b;
        n++;
      }
    }
    return n == 0 ? 128 : sum / n;
  }

  void _setHint(String hint) {
    if (mounted && _hint != hint) setState(() => _hint = hint);
  }

  /// Live pipeline state, shown on screen so issues are diagnosable without
  /// a PC. Sample every few frames to avoid UI churn.
  void _updateDiag({
    required int faces,
    required int landmarks,
    double? ratio,
    int? luma,
    double? yaw,
  }) {
    if (_frame % 3 != 0) return;
    final r = ratio == null ? '' : 'w:${(ratio * 100).round()}%';
    final l = luma == null ? '' : ' luma:$luma';
    final y = yaw == null ? '' : ' yaw:${yaw.round()}°';
    final text = 'F:$faces L:$landmarks $r$l$y cap:$_captured/${EnrollmentCaptureGuide.targetSamples}'
        ' rej:$_rejected';
    if (mounted && _diag != text) setState(() => _diag = text);
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
            CameraPreview(_camera!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white24)),
          if (_state == _CaptureState.done)
            _overlay(const Icon(Icons.check_circle_rounded, color: Color(0xFF2FBF71), size: 64),
                'Face enrolled', 'You can now check in with this face.\nsync: $_syncResult')
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
                    if (_diag.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(_diag,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white30, fontSize: 11, fontFamily: 'monospace')),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < EnrollmentCaptureGuide.targetSamples; i++)
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
