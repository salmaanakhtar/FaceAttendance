/// Global app configuration and tunables.
library;

import 'package:camera/camera.dart';

/// Backend base URL. Overridden at build time with
/// --dart-define=API_BASE=... (production: https://faceattendance-api.salmaan.dev).
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://faceattendance-api.salmaan.dev',
);

/// App release tag (git tag of the GitHub release this build came from).
/// Injected at build time by scripts/publish_release.ps1. Changing this
/// value triggers the one-time local-data wipe in main.dart (forces
/// re-enrollment — required for template v2).
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'v1.1.11',
);

/// ONNX recognition model (bundled asset). InsightFace MobileFaceNet,
/// input [1,3,112,112] NCHW BGR in [-1,1], output 512-d embedding.
/// The ONNX output node is named '516' but the tensor shape is [1,512].
const String kModelAsset = 'assets/models/w600k_mbf.onnx';

/// Recognition thresholds. Calibrated against a real benchmark of this exact
/// model (docs/accuracy.md): with correct preprocessing, cross-person
/// (impostor) cosine similarity peaks around 0.17 even under heavy
/// kiosk-like degradation, while genuine scores average ~0.5+. The old
/// 0.38 threshold sat inside the impostor tail and is the root cause of
/// users being checked in as someone else.
const double kAcceptThreshold = 0.45; // cosine similarity to accept
const double kAmbiguityMargin = 0.10; // min gap between top-1 and top-2

/// Template schema version. Bumped when the embedding pipeline changes
/// (e.g. v2 = corrected BGR channel order). The matcher ignores templates
/// with a different version so stale/buggy templates can never be matched.
const int kTemplateVersion = 2;

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
