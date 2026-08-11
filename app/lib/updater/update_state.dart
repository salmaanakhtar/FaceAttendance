import 'package:flutter/foundation.dart';

import 'update_checker.dart';

enum UpdatePhase { checking, idle, available, downloading, downloaded, error }

/// Holds the app-update state machine: checked → available → downloading →
/// downloaded → install handed to the OS.
class UpdateState extends ChangeNotifier {
  UpdateState._();
  static final UpdateState instance = UpdateState._();

  UpdatePhase phase = UpdatePhase.idle;
  UpdateInfo? info;
  double progress = 0;
  String? error;
  String? _downloadedPath;

  Future<void> check() async {
    if (phase != UpdatePhase.idle && phase != UpdatePhase.checking) return;
    phase = UpdatePhase.checking;
    notifyListeners();
    final result = await UpdateChecker.instance.check();
    if (result == null) {
      phase = UpdatePhase.idle;
    } else if (result.upToDate || result.assetId == null) {
      phase = UpdatePhase.idle;
    } else {
      phase = UpdatePhase.available;
      info = result;
    }
    notifyListeners();
  }

  /// Called from the "Install now" pill after a completed download.
  Future<void> installDownloaded() async {
    final path = _downloadedPath;
    if (phase != UpdatePhase.downloaded || path == null) return;
    try {
      final ok = await UpdateChecker.instance.install(path);
      if (!ok) {
        error = 'installer did not start — allow "install unknown apps" for FaceAttendance';
        phase = UpdatePhase.error;
        notifyListeners();
      }
    } catch (e) {
      error = 'install failed: $e';
      phase = UpdatePhase.error;
      notifyListeners();
    }
  }

  /// Full flow from the "Install" pill on the available banner.
  Future<void> downloadAndInstall() async {
    final assetId = info?.assetId;
    if (phase != UpdatePhase.available || assetId == null) return;
    phase = UpdatePhase.downloading;
    progress = 0;
    notifyListeners();
    try {
      final path = await UpdateChecker.instance.download(assetId, (f) {
        progress = f;
        notifyListeners();
      });
      _downloadedPath = path;
      phase = UpdatePhase.downloaded;
      notifyListeners();
      // Hand straight to the installer after a short beat so the UI repaints.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await installDownloaded();
    } catch (e) {
      error = 'download failed: $e';
      phase = UpdatePhase.error;
      notifyListeners();
    }
  }

  void dismiss() {
    phase = UpdatePhase.idle;
    info = null;
    notifyListeners();
  }
}
