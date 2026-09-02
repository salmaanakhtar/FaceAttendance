import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_state.dart';
import 'app_time.dart';
import 'config.dart';
import 'device/secure_store.dart';
import 'attendance/offline_queue.dart';
import 'ui/admin/admin_gate.dart';
import 'ui/provision/provision_screen.dart';
import 'ui/scanner/code_punch_screen.dart';
import 'recognition/template_store.dart';
import 'updater/update_state.dart';

/// Record the installed build tag without destroying kiosk identity. An app
/// update must keep the device key/token and any offline scans; templates are
/// version-gated and replaced by the normal server sync on bootstrap. Wiping
/// credentials here used to send every updated kiosk back to provisioning.
Future<void> _recordBuildVersion() async {
  final prev = await SecureStore.instance.getInstalledVersion();
  if (prev == kAppVersion) return;
  await SecureStore.instance.setInstalledVersion(kAppVersion);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await _recordBuildVersion();
  await SecureStore.instance.ensureTemplateKey();
  await AppTime.init(); // org-local time for every screen
  await OfflineQueue.instance.init();
  await TemplateStore.instance.init();
  await StatusCache.instance.init();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const FaceAttendanceApp());
}

class FaceAttendanceApp extends StatefulWidget {
  const FaceAttendanceApp({super.key});

  @override
  State<FaceAttendanceApp> createState() => _FaceAttendanceAppState();
}

class _FaceAttendanceAppState extends State<FaceAttendanceApp> {
  bool _provisioned = false;
  bool _checkingProvision = true;

  @override
  void initState() {
    super.initState();
    AppState.instance.start();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final key = await SecureStore.instance.getDeviceKey();
    final token = await SecureStore.instance.getDeviceToken();
    _provisioned = key != null && key.isNotEmpty && token != null;

    if (_provisioned) {
      // Sync templates before opening the camera so the first scan cannot run
      // against an empty or stale local matcher.
      try {
        await TemplateStore.instance.syncFromServer();
      } catch (_) {
        // offline — sync later via the periodic loop
      }
      OfflineQueue.instance.flush();
      // GitHub-backed auto-update check (non-blocking).
      UpdateState.instance.check();
    }
    if (mounted) setState(() => _checkingProvision = false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FaceAttendance',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2F6BFF),
          surface: Color(0xFF0E1116),
        ),
        useMaterial3: true,
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_checkingProvision) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0D10),
        body: Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }
    if (!_provisioned) {
      return ProvisionScreen(
        onProvisioned: () async {
          setState(() => _provisioned = true);
        },
      );
    }

    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        if (AppState.instance.adminMode) {
          // NOT const: the gate must rebuild when login state changes
          // (a const instance would be identical and skipped by Flutter).
          // ignore: prefer_const_constructors
          return AdminGate();
        }
        return CodePunchScreen(
          onAdminRequested: () => AppState.instance.enterAdmin(),
        );
      },
    );
  }
}
