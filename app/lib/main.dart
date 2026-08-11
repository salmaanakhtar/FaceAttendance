import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_state.dart';
import 'attendance/scan_flow.dart';
import 'device/secure_store.dart';
import 'recognition/template_store.dart';
import 'attendance/offline_queue.dart';
import 'ui/admin/admin_gate.dart';
import 'ui/provision/provision_screen.dart';
import 'ui/scanner/scanner_screen.dart';
import 'updater/update_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await SecureStore.instance.ensureTemplateKey();
  await OfflineQueue.instance.init();
  await TemplateStore.instance.init();
  await StatusCache.instance.init();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final cameras = await availableCameras();
  if (cameras.isEmpty) {
    runApp(const _FatalApp(message: 'No camera found on this device.'));
    return;
  }
  // Selfie camera first: the kiosk faces the employee.
  final camera = cameras.firstWhere(
    (c) => c.lensDirection == CameraLensDirection.front,
    orElse: () => cameras.first,
  );

  runApp(FaceAttendanceApp(camera: camera));
}

class _FatalApp extends StatelessWidget {
  final String message;
  const _FatalApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0D10),
        body: Center(
          child: Text(message, style: const TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }
}

class FaceAttendanceApp extends StatefulWidget {
  final CameraDescription camera;
  const FaceAttendanceApp({super.key, required this.camera});

  @override
  State<FaceAttendanceApp> createState() => _FaceAttendanceAppState();
}

class _FaceAttendanceAppState extends State<FaceAttendanceApp> {
  late final ScanFlowController _scanner;
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

    _scanner = ScanFlowController(widget.camera);
    if (_provisioned) {
      await _scanner.init();
      // Kick off template sync + status
      try {
        await TemplateStore.instance.syncFromServer();
      } catch (_) {
        // offline — sync later via the periodic loop
      }
      schedulePeriodicTemplateSync();
      OfflineQueue.instance.flush();
      // GitHub-backed auto-update check (non-blocking).
      UpdateState.instance.check();
    }
    if (mounted) setState(() => _checkingProvision = false);
  }

  @override
  void dispose() {
    _scanner.dispose();
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
          _scanner.init();
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
        return ScannerScreen(
          controller: _scanner,
          onAdminRequested: () => AppState.instance.enterAdmin(),
        );
      },
    );
  }
}
