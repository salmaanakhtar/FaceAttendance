import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_state.dart';
import 'app_time.dart';
import 'config.dart';
import 'device/secure_store.dart';
import 'device/api.dart';
import 'attendance/offline_queue.dart';
import 'ui/admin/admin_gate.dart';
import 'ui/provision/provision_screen.dart';
import 'ui/scanner/code_punch_screen.dart';
import 'recognition/template_store.dart';
import 'updater/update_state.dart';

/// Record the installed build tag without destroying kiosk identity. An app
/// update must keep the device key/token and any offline scans; templates are
/// version-gated and replaced by server sync when needed. Wiping
/// credentials here used to send every updated kiosk back to provisioning.
Future<void> _recordBuildVersion() async {
  final prev = await SecureStore.instance.getInstalledVersion();
  if (prev == kAppVersion) return;
  await SecureStore.instance.setInstalledVersion(kAppVersion);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupScreen());
}

Future<void> initializeLocalStores() async {
  await Hive.initFlutter();
  await _recordBuildVersion();
  await SecureStore.instance.ensureTemplateKey();
  await AppTime.init(); // org-local time for every screen
  await OfflineQueue.instance.init();
  await TemplateStore.instance.init();
  await StatusCache.instance.init();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, this.initialize = initializeLocalStores});
  final Future<void> Function() initialize;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  late Future<void> _initialization = widget.initialize();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return const FaceAttendanceApp();
          }
          return MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Center(
                child: snapshot.connectionState == ConnectionState.done && snapshot.hasError
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Could not open local attendance storage.'),
                        const Text(
                            'Your saved data has been kept. Please retry.'),
                        TextButton(
                          onPressed: () => setState(() {
                            _initialization = widget.initialize();
                          }),
                          child: const Text('Retry'),
                        ),
                      ])
                    : const CircularProgressIndicator(),
              ),
            ),
          );
        },
      );
}

class FaceAttendanceApp extends StatefulWidget {
  const FaceAttendanceApp({super.key});

  @override
  State<FaceAttendanceApp> createState() => _FaceAttendanceAppState();
}

class _FaceAttendanceAppState extends State<FaceAttendanceApp> {
  bool _provisioned = false;
  bool _checkingProvision = true;
  bool _provisionError = false;

  @override
  void initState() {
    super.initState();
    AppState.instance.start();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final key = await SecureStore.instance.getDeviceKey();
      final token = await SecureStore.instance.getDeviceToken();
      _provisioned =
          key != null && key.isNotEmpty && token != null && token.isNotEmpty;
      _provisionError = false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _provisionError = true;
          _checkingProvision = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _checkingProvision = false);

    if (_provisioned) {
      // Refresh the organization timezone and calibrate the visible clock
      // against server time. Stored values remain available when offline.
      try {
        await ApiClient.instance.fetchConfig();
      } catch (_) {
        // offline — AppTime keeps the last successful timezone/clock offset
      }
      // The code keypad does not require a face-template download.
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
    if (_provisionError) {
      return Scaffold(
          body: Center(
              child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not read device setup. Please retry.'),
          TextButton(onPressed: _bootstrap, child: const Text('Retry')),
        ],
      )));
    }
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
          await _bootstrap();
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
