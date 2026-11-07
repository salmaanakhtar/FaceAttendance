import 'dart:async';
import 'dart:math' show Point;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../device/api.dart';
import '../recognition/embedder.dart';
import '../recognition/liveness.dart';
import '../recognition/template_store.dart';
import '../util/feedback.dart';
import 'offline_queue.dart';

enum ScanPhase {
  init, // loading model / camera
  idle, // watching, no face
  faceDetected, // face in frame, gating quality
  scanning, // collecting samples for liveness + matching
  recognized, // matched — about to submit
  submitting, // contacting server / queueing
  checkIn,
  checkOut,
  unknown,
  ambiguous,
  multipleFaces,
  faceTooFar,
  poorLighting,
  livenessFailed,
  networkUnavailable,
  backendFailure,
  duplicate,
  alreadyIn,
  alreadyOut,
  offline, // device offline (queued)
}

class ScanOutcome {
  final ScanPhase phase;
  final String? employeeId;
  final String? employeeName;
  final DateTime? at;
  final String? message;
  final double? score;
  ScanOutcome({
    required this.phase,
    this.employeeId,
    this.employeeName,
    this.at,
    this.message,
    this.score,
  });
}

/// The scanner's brain: camera frame pipeline -> detection -> quality gates
/// -> liveness -> embedding -> match -> server/queue -> feedback.
class ScanFlowController extends ChangeNotifier {
  ScanFlowController(this.cameras);

  final List<CameraDescription> cameras;
  CameraController? _camera;
  FaceDetector? _detector;
  Timer? _cooldownTimer;
  bool _disposed = false;
  bool _busy = false;
  bool _initializing = false;

  ScanPhase phase = ScanPhase.init;
  ScanOutcome? outcome;
  double? lastConfidence;
  bool lastSyncWasOffline = false;
  bool modelReady = false;
  String? initError;
  CameraDescription? selectedCamera;

  ({Uint8List bytes, int width, int height})? _lastFrame;
  int _frameCount = 0;
  bool _presenceLock = false; // re-scan only after the face leaves the frame

  CameraController? get camera => _camera;
  bool get isFrontCamera =>
      selectedCamera?.lensDirection == CameraLensDirection.front;

  Future<void> init() async {
    if (_disposed || _initializing) return;
    _initializing = true;
    try {
      modelReady = true;
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          // Fast mode keeps the kiosk responsive; quality gates still reject
          // weak captures before a frame is sent to Rekognition.
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: true,
          enableClassification: true,
        ),
      );
      // Selfie camera first (the kiosk faces the employee); fall back
      // through the remaining cameras if the front one cannot open.
      final ordered = [
        ...cameras.where((c) => c.lensDirection == CameraLensDirection.front),
        ...cameras.where((c) => c.lensDirection != CameraLensDirection.front),
      ];
      CameraController? opened;
      for (final candidate in ordered) {
        final c = CameraController(
          candidate,
          kCameraResolution,
          enableAudio: false,
          // NV21: the only byte format ML Kit's fromByteArray accepts.
          imageFormatGroup: ImageFormatGroup.nv21,
        );
        try {
          await c.initialize();
          opened = c;
          selectedCamera = candidate;
          break;
        } catch (e) {
          debugPrint('camera ${candidate.name} failed to open: $e');
          await c.dispose();
        }
      }
      if (opened == null) {
        initError = 'no usable camera';
        phase = ScanPhase.init;
        notifyListeners();
        return;
      }
      _camera = opened;
      await _camera!.setFlashMode(FlashMode.off);
      _camera!.startImageStream(_onFrame);
      phase = ScanPhase.idle;
      notifyListeners();
    } catch (e) {
      initError = 'camera init failed: $e';
      phase = ScanPhase.init;
      notifyListeners();
    } finally {
      _initializing = false;
    }
  }

  void setOnline(bool online) {
    OfflineQueue.instance.setOnline(online);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_disposed || _busy) return;
    final detector = _detector;
    final camera = _camera;
    if (detector == null || camera == null) return;

    _busy = true;
    try {
      // Detection: feed ML Kit the raw NV21 buffer with rotation metadata —
      // the supported path. Coordinates come back in the upright space.
      final rotationDeg = selectedCamera!.sensorOrientation % 360;
      final inputImage = InputImage.fromBytes(
        bytes: nv21Of(image),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.values[rotationDeg ~/ 90],
          format: InputImageFormat.nv21,
          // NV21 is tightly packed; providing the actual row stride helps ML
          // Kit decode frames consistently across camera implementations.
          bytesPerRow: image.width,
        ),
      );
      final faces = await detector.processImage(inputImage).timeout(
            const Duration(seconds: 4),
          );

      if (faces.isEmpty) {
        // Face left the frame — clear the presence lock so the next person
        // can scan.
        if (_presenceLock) {
          _presenceLock = false;
          _resetScan();
          phase = ScanPhase.idle;
          notifyListeners();
        }
        return;
      }
      if (faces.length > 1) {
        if (phase != ScanPhase.submitting) {
          _resetScan();
          phase = ScanPhase.multipleFaces;
          notifyListeners();
        }
        return;
      }

      // Presence lock: after any scan outcome, do not re-scan while the
      // same person is still standing in front of the camera.
      if (_presenceLock) return;

      final face = faces.first;
      final faceBox = face.boundingBox;
      // Embedding crop: same rotation as ML Kit (no mirror — the raw sensor
      // buffer is unmirrored, so upright spaces match exactly).
      final upright = yuvToUprightRgba(image, rotationDeg, mirrorX: false);
      final meanLuma = _meanLuma(upright.bytes, upright.width, upright.height);
      final issue = ScanQuality.check(
        faceWidthPx: faceBox.width.round(),
        frameWidthPx: upright.width,
        meanLuma: meanLuma,
      );
      switch (issue) {
        case QualityIssue.tooFar:
          if (phase != ScanPhase.submitting) {
            _resetScan();
            phase = ScanPhase.faceTooFar;
            notifyListeners();
          }
          return;
        case QualityIssue.poorLighting:
          if (phase != ScanPhase.submitting) {
            _resetScan();
            phase = ScanPhase.poorLighting;
            notifyListeners();
          }
          return;
        case QualityIssue.multipleFaces:
          return;
        case QualityIssue.none:
          break;
      }

      // We have a good single face. Start a scan session.
      if (phase != ScanPhase.scanning && phase != ScanPhase.submitting) {
        phase = ScanPhase.scanning;
        notifyListeners();
        await FeedbackFx.scanCapture();
      }
      if (phase != ScanPhase.scanning) return;

      // Sharpness gate: skip blurry frames so they never pollute the fused
      // embedding (motion blur while the subject moves is the main cause of
      // unreliable scans).
      final sharpness = ImageSharpness.faceRegionSharpness(
        upright.bytes,
        upright.width,
        upright.height,
        faceBox.left.round(),
        faceBox.top.round(),
        faceBox.width.round(),
        faceBox.height.round(),
      );
      if (!ImageSharpness.acceptable(sharpness)) return;

      final landmarks = _landmarkOffsets(face, faceBox);
      if (landmarks.length != 5) return;

      // No liveness gate in v1: the frame is sent to Rekognition after the
      // quality/sharpness checks. Keep the last accepted frame for upload.
      _lastFrame = upright;
      _frameCount++;
      if (_frameCount >= kMinSamples) {
        await _finishScan();
      }
    } catch (e) {
      debugPrint('scan frame error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _finishScan() async {
    if (phase == ScanPhase.submitting) return;
    final frame = _lastFrame;
    if (frame == null) return;
    phase = ScanPhase.submitting;
    notifyListeners();

    Uint8List jpeg;
    try {
      final bitmap = img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.bytes.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      jpeg = img.encodeJpg(bitmap, quality: 82);
    } catch (error) {
      outcome = ScanOutcome(
        phase: ScanPhase.backendFailure,
        message: 'Could not prepare the face image — try again',
      );
      phase = ScanPhase.backendFailure;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    }

    Map<String, dynamic> result;
    try {
      result = await ApiClient.instance.recognizeFace(
        jpeg: jpeg,
        dedupeKey: const Uuid().v4(),
      );
    } on OfflineException {
      outcome = ScanOutcome(
        phase: ScanPhase.networkUnavailable,
        message: 'Face check-in is offline — use worker code',
      );
      phase = ScanPhase.networkUnavailable;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    } on ServerException catch (error) {
      outcome = ScanOutcome(
        phase: ScanPhase.backendFailure,
        message: error.status == 429
            ? 'Please wait a moment'
            : 'Face service unavailable — use worker code',
      );
      phase = ScanPhase.backendFailure;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    }

    final action = result['action'] as String? ?? 'unknown';
    final employee = result['employee'] as Map<String, dynamic>?;
    final employeeId = employee?['id'] as String?;
    final name = employee?['name'] as String? ?? '';
    final at = DateTime.tryParse(result['scanTime'] as String? ?? '');
    final match = result['match'] as Map<String, dynamic>?;
    final similarity = (match?['similarity'] as num?)?.toDouble();
    lastConfidence = similarity == null ? null : similarity / 100;
    lastSyncWasOffline = false;

    switch (action) {
      case 'check_in':
        if (employeeId != null) {
          StatusCache.instance.recordOutcome(
              employeeId, action, at ?? DateTime.now());
        }
        outcome = ScanOutcome(
            phase: ScanPhase.checkIn,
            employeeId: employeeId,
            employeeName: name,
            at: at);
        phase = ScanPhase.checkIn;
        await FeedbackFx.success();
        unawaited(FeedbackFx.speak('Welcome $name'));
        break;
      case 'check_out':
        if (employeeId != null) {
          StatusCache.instance.recordOutcome(
              employeeId, action, at ?? DateTime.now());
        }
        outcome = ScanOutcome(
            phase: ScanPhase.checkOut,
            employeeId: employeeId,
            employeeName: name,
            at: at);
        phase = ScanPhase.checkOut;
        await FeedbackFx.success();
        unawaited(FeedbackFx.speak('Goodbye $name'));
        break;
      case 'duplicate':
        outcome = ScanOutcome(
            phase: ScanPhase.duplicate,
            employeeId: employeeId,
            employeeName: name,
            message: result['message'] as String?);
        phase = ScanPhase.duplicate;
        await FeedbackFx.error();
        break;
      case 'already_in':
        outcome = ScanOutcome(
            phase: ScanPhase.alreadyIn,
            employeeId: employeeId,
            employeeName: name,
            at: at);
        phase = ScanPhase.alreadyIn;
        await FeedbackFx.error();
        break;
      case 'already_out':
        outcome = ScanOutcome(
            phase: ScanPhase.alreadyOut,
            employeeId: employeeId,
            employeeName: name,
            at: at);
        phase = ScanPhase.alreadyOut;
        await FeedbackFx.error();
        break;
      case 'ambiguous':
        outcome = ScanOutcome(
          phase: ScanPhase.ambiguous,
          message: 'Face match is unclear — try again or use worker code',
        );
        phase = ScanPhase.ambiguous;
        await FeedbackFx.error();
        break;
      default:
        outcome = ScanOutcome(
          phase: ScanPhase.unknown,
          message: 'Face not recognized — use worker code or ask an admin',
        );
        phase = ScanPhase.unknown;
        await FeedbackFx.error();
    }

    notifyListeners();
    _resetScan();
    _scheduleCooldown();
  }

  /// 5 alignment points. Prefers ML Kit landmarks; falls back to face-box
  /// geometry so the flow can never stall on missing landmarks.
  List<Offset> _landmarkOffsets(Face face, Rect box) {
    final lm = face.landmarks;
    Point<int>? get(FaceLandmarkType t) => lm[t]?.position;
    final lEye = get(FaceLandmarkType.leftEye);
    final rEye = get(FaceLandmarkType.rightEye);
    final nose = get(FaceLandmarkType.noseBase);
    final lMouth = get(FaceLandmarkType.leftMouth);
    final rMouth = get(FaceLandmarkType.rightMouth);
    if (lEye != null &&
        rEye != null &&
        nose != null &&
        lMouth != null &&
        rMouth != null) {
      return [
        Offset(lEye.x.toDouble(), lEye.y.toDouble()),
        Offset(rEye.x.toDouble(), rEye.y.toDouble()),
        Offset(nose.x.toDouble(), nose.y.toDouble()),
        Offset(lMouth.x.toDouble(), lMouth.y.toDouble()),
        Offset(rMouth.x.toDouble(), rMouth.y.toDouble()),
      ];
    }
    // Fallback: proportional face-box geometry.
    final x = box.left.toDouble();
    final y = box.top.toDouble();
    final bw = box.width.toDouble();
    final bh = box.height.toDouble();
    return [
      Offset(x + 0.33 * bw, y + 0.30 * bh),
      Offset(x + 0.67 * bw, y + 0.30 * bh),
      Offset(x + 0.50 * bw, y + 0.50 * bh),
      Offset(x + 0.38 * bw, y + 0.72 * bh),
      Offset(x + 0.62 * bw, y + 0.72 * bh),
    ];
  }

  double _meanLuma(Uint8List bgra, int w, int h) {
    // True BT.601 luma from the BGRA frame (weighted R/G/B, not a single
    // color channel — the blue channel alone is a poor brightness proxy).
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

  void _resetScan() {
    _lastFrame = null;
    _frameCount = 0;
  }

  void _scheduleCooldown() {
    _presenceLock = true; // no re-scan until the face leaves the frame
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(
        const Duration(milliseconds: kResultHoldMs + kScanCooldownMs), () {
      _resetScan();
      outcome = null;
      phase = ScanPhase.idle;
      notifyListeners();
    });
  }

  /// Free the camera while admin surfaces (or enrollment) use it.
  void pause() {
    _cooldownTimer?.cancel();
    _camera?.stopImageStream();
    phase = ScanPhase.init;
    notifyListeners();
  }

  /// Restore the live scanner after admin work.
  Future<void> resume() async {
    final camera = _camera;
    if (camera == null || camera.value.isInitialized) {
      if (camera != null && !camera.value.isStreamingImages) {
        camera.startImageStream(_onFrame);
        phase = ScanPhase.idle;
        notifyListeners();
      }
      return;
    }
    await init();
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    _detector?.close();
    super.dispose();
  }
}
