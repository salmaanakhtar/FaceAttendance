import 'package:flutter/material.dart';

import '../../admin/admin_api.dart';
import '../../app_state.dart';

/// Phase-3 placeholder shell for admin surfaces. Lock icon in the app bar
/// returns the kiosk to the scanner (auto-relock also enforced).
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && AppState.instance.adminMode) {
      AppState.instance.lockToKiosk();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Lock kiosk',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: () async {
              await AdminApi.instance.logout();
              AppState.instance.lockToKiosk();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Admin console coming online\nin the next build cycle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => AppState.instance.lockToKiosk(),
              child: const Text('Return to scanner', style: TextStyle(color: Color(0xFF4DA3FF))),
            ),
          ],
        ),
      ),
    );
  }
}
