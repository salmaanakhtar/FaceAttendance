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
  bool _initializing = false;

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
  bool _presenceLock = false; // re-scan only after the face leaves the frame
  int _embedFails = 0;

  CameraController? get camera => _camera;
  bool get isFrontCamera =>
      selectedCamera?.lensDirection == CameraLensDirection.front;

  Future<void> init() async {
    if (_disposed || _initializing) return;
    _initializing = true;
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
          // Fast mode keeps the kiosk responsive; quality gates and the
          // embedding matcher still reject weak or ambiguous captures.
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
    final embedder = _embedder;
    final camera = _camera;
    if (detector == null || embedder == null || camera == null) return;

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
      if (embedding == null) {
        // A face is in frame but the model keeps refusing frames. Surface
        // it instead of hanging on "Scanning…" forever.
        _embedFails++;
        if (_embedFails > 30 && phase != ScanPhase.submitting) {
          _resetScan();
          outcome = ScanOutcome(
            phase: ScanPhase.backendFailure,
            message: 'face recognition engine stalled — restart the kiosk',
          );
          phase = ScanPhase.backendFailure;
          notifyListeners();
          _scheduleCooldown();
        }
        return;
      }
      _embedFails = 0;
      _samples.add(embedding);
      // Progressive matching is expensive on large employee lists. Only
      // calculate it at the decision point; the final match remains unchanged.
      if (_samples.length == kMinSamples) {
        lastConfidence = _progressiveScore(_samples);
      }

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

    final fused = robustFuse(_samples);
    final match = matchEmbedding(fused, TemplateStore.instance.candidates());

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
    lastLiveness = (_liveness.blinks / kMinBlinks).clamp(0.0, 1.0);
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
      if (e.status == 429) {
        // Rate limited — the kiosk is being scanned too fast. Show a calm
        // "wait" state instead of an error.
        outcome = ScanOutcome(
          phase: ScanPhase.duplicate,
          employeeId: match.employeeId,
          employeeName: template?.name,
          message: 'Please wait a moment',
        );
        phase = ScanPhase.duplicate;
        notifyListeners();
        _resetScan();
        _scheduleCooldown();
        return;
      }
      outcome = ScanOutcome(
          phase: ScanPhase.backendFailure,
          employeeId: match.employeeId,
          message: 'server $e');
      phase = ScanPhase.backendFailure;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    } on OfflineException {
      // Should not happen — enqueue returns queued instead. Safety net.
      outcome =
          ScanOutcome(phase: ScanPhase.offline, employeeId: match.employeeId);
      phase = ScanPhase.offline;
      notifyListeners();
      await FeedbackFx.error();
      _resetScan();
      _scheduleCooldown();
      return;
    }

    // OfflineQueue intentionally returns only `{queued: true}` until the
    // server is reachable. Preserve the locally selected direction so the
    // kiosk can still give an accurate immediate confirmation; the server
    // remains authoritative when the event is flushed.
    final action = result['action'] as String? ??
        (queued ? (direction == 'out' ? 'check_out' : 'check_in') : 'unknown');
    final serverTime = result['scanTime'] as String?;
    final at = serverTime != null ? DateTime.tryParse(serverTime) : null;
    final name = template?.name ?? '';
    lastSyncWasOffline = queued;

    StatusCache.instance
        .recordOutcome(match.employeeId!, action, at ?? DateTime.now());

    switch (action) {
      case 'check_in':
        outcome = ScanOutcome(
            phase: ScanPhase.checkIn,
            employeeId: match.employeeId,
            employeeName: name,
            at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.checkIn;
        await FeedbackFx.success();
        unawaited(FeedbackFx.speak('Welcome $name'));
        break;
      case 'check_out':
        outcome = ScanOutcome(
            phase: ScanPhase.checkOut,
            employeeId: match.employeeId,
            employeeName: name,
            at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.checkOut;
        await FeedbackFx.success();
        unawaited(FeedbackFx.speak('Goodbye $name'));
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
            phase: ScanPhase.alreadyIn,
            employeeId: match.employeeId,
            employeeName: name,
            at: at);
        phase = queued ? ScanPhase.offline : ScanPhase.alreadyIn;
        if (!queued) await FeedbackFx.error();
        break;
      case 'already_out':
        outcome = ScanOutcome(
            phase: ScanPhase.alreadyOut,
            employeeId: match.employeeId,
            employeeName: name,
            at: at);
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
    _samples.clear();
    _liveness.reset();
    _embedFails = 0;
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
