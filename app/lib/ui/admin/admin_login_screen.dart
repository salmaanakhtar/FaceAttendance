import 'package:flutter/material.dart';

import '../../admin/admin_api.dart';
import '../../app_state.dart';
import '../../device/secure_store.dart';
import '../../util/feedback.dart';

/// Admin sign-in: the only gate between the scanner and admin surfaces.
/// Server-validated credentials; session is revocable server-side.
class AdminLoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const AdminLoginScreen({super.key, required this.onSuccess});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminApi.instance.login(
        _username.text.trim(),
        _password.text,
        deviceId: await SecureStore.instance.getDeviceId(),
      );
      await FeedbackFx.adminUnlock();
      if (mounted) widget.onSuccess();
    } catch (e) {
      setState(() => _error = 'Sign-in failed. Check your credentials.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'Admin access',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Restricted — attendance records are audited',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _username,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white),
                    decoration: _field('Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(color: Colors.white),
                    decoration: _field('Password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF5D5D), fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6BFF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => AppState.instance.lockToKiosk(),
                    child: const Text('Back to scanner', style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF161A20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2F6BFF)),
        ),
      );
}
