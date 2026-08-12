import 'package:flutter/foundation.dart';

import 'update_checker.dart';

enum UpdatePhase { idle, downloading, installing }
/// Fully automatic updater: checks on launch, downloads silently, installs
/// through the system installer, and the app relaunches automatically after
/// the package is replaced. No user-facing buttons or banners.
class UpdateState extends ChangeNotifier {
  UpdateState._();
  static final UpdateState instance = UpdateState._();

  UpdatePhase phase = UpdatePhase.idle;
  double progress = 0;
  String? error;

  Future<void> check() async {
    if (phase != UpdatePhase.idle) return;
    final info = await UpdateChecker.instance.check();
    if (info == null || info.upToDate || info.assetId == null) return;
    phase = UpdatePhase.downloading;
    progress = 0;
    notifyListeners();
    try {
      final path = await UpdateChecker.instance.download(info.assetId!, (f) {
        progress = f;
        notifyListeners();
      });
      // Let the UI repaint the 100% state, then hand to the installer.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      phase = UpdatePhase.installing;
      notifyListeners();
      await UpdateChecker.instance.install(path);
      // The system installer takes over; MY_PACKAGE_REPLACED relaunches us.
      phase = UpdatePhase.idle;
      notifyListeners();
    } catch (e) {
      error = '$e';
      phase = UpdatePhase.idle;
      notifyListeners();
    }
  }
}
