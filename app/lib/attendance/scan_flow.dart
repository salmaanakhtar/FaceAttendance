import 'dart:async';
import 'dart:math' show Point;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../config.dart';
import '../device/api.dart';
import '../recognition/embedder.dart';
import '../recognition/liveness.dart';
import '../recognition/matcher.dart';
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
  FaceEmbedder? _embedder;
  Timer? _cooldownTimer;
  bool _disposed = false;
  bool _busy = false;

  ScanPhase phase = ScanPhase.init;
  ScanOutcome? outcome;
  double? lastConfidence;
  double? lastLiveness;
  bool lastSyncWasOffline = false;
  bool modelReady = false;
  String? initError;
  CameraDescription? selectedCamera;

  final LivenessTracker _liveness = LivenessTracker();
  final List<List<double>> _samples = [];
  int _lastStatusUpdate = 0;

  CameraController? get camera => _camera;
  bool get isFrontCamera => selectedCamera?.lensDirection == CameraLensDirection.front;

  Future<void> init() async {
    try {
      _embedder = FaceEmbedder();
      await _embedder!.init();
      modelReady = _embedder!.ready;
      if (!modelReady) {
        initError = _embedder!.error;
        phase = ScanPhase.init;
        notifyListeners();
        return;
      }
      _detector = FaceDetector(
        options: FaceDetectorOptions(
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
          imageFormatGroup: ImageFormatGroup.yuv420,
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
    }
  }

  void setOnline(bool online) {
    OfflineQueue.instance.setOnline(online);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_disposed || _busy) return;
    final detector = _detector;
    final embedder = _embedder;
    final camera = _camera;
    if (detector == null || embedder == null || camera == null) return;

    _busy = true;
    try {
      // Upright conversion once per frame (rotation + front-camera mirror).
      final rotation = selectedCamera!.sensorOrientation % 360;
      final isFront = selectedCamera!.lensDirection == CameraLensDirection.front;
      final upright = yuvToUprightRgba(image, rotation, mirrorX: isFront);
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

      // Live status tick (cheap; ~4/s).
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastStatusUpdate > 250) {
        _lastStatusUpdate = nowMs;
        if (faces.isEmpty) {
          if (phase == ScanPhase.faceDetected || phase == ScanPhase.scanning) {
            _resetScan();
            phase = ScanPhase.idle;
            notifyListeners();
          }
        }
        notifyListeners();
      }

      if (faces.isEmpty) return;
      if (faces.length > 1) {
        if (phase != ScanPhase.submitting) {
          _resetScan();
          phase = ScanPhase.multipleFaces;
          notifyListeners();
        }
        return;
      }

      final face = faces.first;
      final faceBox = face.boundingBox;
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

      final landmarks = _landmarkOffsets(face);
      if (landmarks == null || landmarks.length != 5) return;

      _liveness.observe(
        leftOpen: face.leftEyeOpenProbability ?? 0.5,
        rightOpen: face.rightEyeOpenProbability ?? 0.5,
      );

      final embedding = embedder.embed(
        rgba: upright.bytes,
        width: upright.width,
        height: upright.height,
        landmarks: landmarks,
      );
      if (embedding == null) return;
      _samples.add(embedding);
      lastConfidence = _progressiveScore(_samples);

      if (_liveness.isSatisfied && _samples.length >= kMinSamples) {
        await _finishScan(embedder);
      } else if (_samples.length >= kMaxSamples) {
        // Ran out of frames without liveness — fail the session.
        phase = ScanPhase.livenessFailed;
        notifyListeners();
        await FeedbackFx.error();
        _scheduleCooldown();
      }
    } catch (e) {
      debugPrint('scan frame error: $e');
    } finally {
      _busy = false;
    }
  }

  /// Progress score for the live indicator: best cosine of the fused-so-far
  /// against the best template — monotonic-ish, cheap.
  double _progressiveScore(List<List<double>> samples) {
    if (samples.length < 2) return 0.0;
    final fused = fuseEmbeddings(samples);
    var best = 0.0;
    for (final t in TemplateStore.instance.all.values) {
      final s = cosineSimilarity(fused, t);
      if (s > best) best = s;
    }
    return best;
  }

  Future<void> _finishScan(FaceEmbedder embedder) async {
    if (phase == ScanPhase.submitting) return;
    phase = ScanPhase.submitting;
    notifyListeners();

    final fused = fuseEmbeddings(_samples);
    final templates = TemplateStore.instance.all;
    final match = matchEmbedding(fused, templates);

    if (!match.matched) {
      if (match.ambiguous) {
        outcome = ScanOutcome(phase: ScanPhase.ambiguous, score: match.score);
      } else {
        outcome = ScanOutcome(phase: ScanPhase.unknown, score: match.score);
      }
      phase = outcome!.phase;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    }

    final template = TemplateStore.instance.byId(match.employeeId!);
    final direction = matcherHint(match.employeeId!);
    phase = ScanPhase.recognized;
    lastConfidence = match.score;
    lastLiveness = _liveness.blinks / kMinBlinks;
    notifyListeners();

    Map<String, dynamic> result;
    bool queued = false;
    try {
      result = await OfflineQueue.instance.enqueue(
        employeeId: match.employeeId!,
        directionHint: direction,
        confidence: match.score,
        livenessScore: lastLiveness,
        faceHash: _faceHash(match.employeeId!),
      );
      queued = result['queued'] == true;
    } on ServerException catch (e) {
      outcome = ScanOutcome(phase: ScanPhase.backendFailure, employeeId: match.employeeId, message: 'server $e');
      phase = ScanPhase.backendFailure;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    } on OfflineException {
      // Should not happen — enqueue returns queued instead. Safety net.
      outcome = ScanOutcome(phase: ScanPhase.offline, employeeId: match.employeeId);
      phase = ScanPhase.offline;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    }

    final action = result['action'] as String? ?? 'unknown';
    final serverTime = result['scanTime'] as String?;
    final at = serverTime != null ? DateTime.tryParse(serverTime) : null;
    final name = template?.name ?? '';
    lastSyncWasOffline = queued;

    StatusCache.instance.recordOutcome(match.employeeId!, action, at ?? DateTime.now());

    switch (action) {
      case 'check_in':
        outcome = ScanOutcome(
            phase: ScanPhase.checkIn, employeeId: match.employeeId, employeeName: name, at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.checkIn;
        if (!queued) await FeedbackFx.success();
        break;
      case 'check_out':
        outcome = ScanOutcome(
            phase: ScanPhase.checkOut, employeeId: match.employeeId, employeeName: name, at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.checkOut;
        if (!queued) await FeedbackFx.success();
        break;
      case 'duplicate':
        outcome = ScanOutcome(
            phase: ScanPhase.duplicate,
            employeeId: match.employeeId,
            employeeName: name,
            message: result['message'] as String?);
        phase = queued ? ScanPhase.offline : ScanPhase.duplicate;
        if (!queued) await FeedbackFx.error();
        break;
      case 'already_in':
        outcome = ScanOutcome(
            phase: ScanPhase.alreadyIn, employeeId: match.employeeId, employeeName: name, at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.alreadyIn;
        if (!queued) await FeedbackFx.error();
        break;
      case 'already_out':
        outcome = ScanOutcome(
            phase: ScanPhase.alreadyOut, employeeId: match.employeeId, employeeName: name, at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.alreadyOut;
        if (!queued) await FeedbackFx.error();
        break;
      default:
        outcome = ScanOutcome(
            phase: ScanPhase.backendFailure,
            employeeId: match.employeeId,
            message: 'unexpected action $action');
        phase = ScanPhase.backendFailure;
        await FeedbackFx.error();
    }
    notifyListeners();
    _resetScan();
    _scheduleCooldown();
  }

  String? _faceHash(String employeeId) {
    return employeeId;
  }

  String? matcherHint(String employeeId) {
    return hintDirection(
      lastDirection: StatusCache.instance.lastDirection(employeeId),
      isCurrentlyIn: StatusCache.instance.isIn(employeeId),
    );
  }

  List<Offset>? _landmarkOffsets(Face face) {
    final lm = face.landmarks;
    if (lm.isEmpty) return null;
    final out = <Offset>[];
    Point<int>? get(FaceLandmarkType t) => lm[t]?.position;
    final lEye = get(FaceLandmarkType.leftEye);
    final rEye = get(FaceLandmarkType.rightEye);
    final nose = get(FaceLandmarkType.noseBase);
    final lMouth = get(FaceLandmarkType.leftMouth);
    final rMouth = get(FaceLandmarkType.rightMouth);
    if (lEye == null || rEye == null || nose == null || lMouth == null || rMouth == null) {
      return null;
    }
    out.addAll([
      Offset(lEye.x.toDouble(), lEye.y.toDouble()),
      Offset(rEye.x.toDouble(), rEye.y.toDouble()),
      Offset(nose.x.toDouble(), nose.y.toDouble()),
      Offset(lMouth.x.toDouble(), lMouth.y.toDouble()),
      Offset(rMouth.x.toDouble(), rMouth.y.toDouble()),
    ]);
    return out;
  }

  double _meanLuma(Uint8List rgba, int w, int h) {
    // Sample a coarse grid of pixels from the Y channel (every R).
    const step = 16;
    var sum = 0.0;
    var n = 0;
    for (var y = 0; y < h; y += step) {
      for (var x = 0; x < w; x += step) {
        sum += rgba[(y * w + x) * 4];
        n++;
      }
    }
    return n == 0 ? 128 : sum / n;
  }

  void _resetScan() {
    _samples.clear();
  }

  void _scheduleCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(milliseconds: kResultHoldMs + kScanCooldownMs), () {
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
