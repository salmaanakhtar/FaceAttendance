import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'attendance/offline_queue.dart';
import 'config.dart';

/// App-wide state: connectivity, admin lock, kiosk wiring.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  bool online = true;
  bool adminMode = false;
  DateTime? _lastAdminActivity;
  Timer? _relockTimer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Called after bootstrap; starts listening to connectivity and the
  /// admin auto-relock countdown.
  void start() {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final nowOnline = results.any((r) => r != ConnectivityResult.none);
      if (nowOnline != online) {
        online = nowOnline;
        if (nowOnline) OfflineQueue.instance.flush();
        notifyListeners();
      }
    });
  }

  void enterAdmin() {
    adminMode = true;
    _touchAdminActivity();
    notifyListeners();
  }

  void touchAdminActivity() {
    if (adminMode) _touchAdminActivity();
  }

  void _touchAdminActivity() {
    _lastAdminActivity = DateTime.now();
    _relockTimer?.cancel();
    _relockTimer = Timer(kAdminInactivityLock, () {
      if (adminMode && _lastAdminActivity != null &&
          DateTime.now().difference(_lastAdminActivity!) >= kAdminInactivityLock) {
        lockToKiosk();
      }
    });
  }

  void lockToKiosk() {
    adminMode = false;
    _relockTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _relockTimer?.cancel();
    super.dispose();
  }
}
