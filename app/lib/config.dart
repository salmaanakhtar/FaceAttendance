/// Global app configuration and tunables.
library;

import 'package:camera/camera.dart';

/// Backend base URL. Android emulator reaches host via 10.0.2.2.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://10.0.2.2:4747',
);

/// ONNX recognition model (bundled asset). InsightFace MobileFaceNet,
/// input [1,3,112,112] NCHW RGB in [-1,1], output 512-d embedding.
const String kModelAsset = 'assets/models/w600k_mbf.onnx';

/// Recognition thresholds (calibrate via docs/accuracy.md).
const double kAcceptThreshold = 0.38; // cosine similarity to accept
const double kAmbiguityMargin = 0.06; // min gap between top-1 and top-2

/// Scan session gating.
const int kMinSamples = 4; // frames collected before matching
const int kMaxSamples = 6;
const double kMinFaceWidthRatio = 0.18; // face box vs frame width
const double kMinBrightness = 28.0; // 0..255 mean luma
const double kMaxBrightness = 235.0;
const int kScanCooldownMs = 2000; // pause after a result
const int kResultHoldMs = 1500; // how long feedback stays on screen

/// Liveness: blink + motion requirements within a scan window.
const int kMinBlinks = 1;
const double kMinBlinkProbability = 0.5; // below this = "eyes closed"

/// Offline queue retry.
const int kMaxQueueRetries = 10;
const Duration kQueueFlushInterval = Duration(seconds: 20);

/// Admin auto-relock after inactivity.
const Duration kAdminInactivityLock = Duration(minutes: 3);

/// Template sync cadence.
const Duration kTemplateSyncInterval = Duration(minutes: 10);

/// Camera pipeline: resolution chosen for cheap YUV->RGB + fast ML.
const ResolutionPreset kCameraResolution = ResolutionPreset.medium; // 640x480
