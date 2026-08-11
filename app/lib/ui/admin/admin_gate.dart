import 'package:flutter/material.dart';

import '../../admin/admin_api.dart';
import '../../app_state.dart';
import 'admin_login_screen.dart';
import 'admin_shell.dart';

/// The admin flow gate — restore a session if possible, otherwise show the
/// login screen. Runs the restore check exactly once per entry.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await AdminApi.instance.tryRestoreSession();
    if (mounted) setState(() => _checked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0D10),
        body: Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }
    if (AdminApi.instance.isLoggedIn) {
      return const AdminShellScreen();
    }
    return AdminLoginScreen(
      onSuccess: () {
        AppState.instance.enterAdmin();
      },
    );
  }
}
