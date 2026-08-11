import 'package:flutter/material.dart';

import '../../config.dart';
import '../../device/api.dart';
import '../../device/secure_store.dart';

/// First-boot provisioning: a device key from the org admin unlocks the
/// kiosk. The key is stored in secure storage and exchanged for a device
/// token on every handshake.
class ProvisionScreen extends StatefulWidget {
  final VoidCallback onProvisioned;
  const ProvisionScreen({super.key, required this.onProvisioned});

  @override
  State<ProvisionScreen> createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _provision() async {
    if (_busy) return;
    final key = _key.text.trim();
    if (key.length < 8) {
      setState(() => _error = 'Enter the device key provided by your administrator.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SecureStore.instance.setDeviceKey(key);
      await ApiClient.instance.handshake();
      if (mounted) widget.onProvisioned();
    } catch (e) {
      await SecureStore.instance.setDeviceKey(''); // don't keep a bad key
      setState(() => _error =
          'Could not reach the server at $kApiBaseUrl. Check that the phone and the server are on the same network, and that the device key is correct.');
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.fingerprint_rounded, color: Colors.white38, size: 40),
                  const SizedBox(height: 16),
                  const Text('Set up this kiosk',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the device key from your administrator to connect this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Server: $kApiBaseUrl',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _key,
                    autofocus: true,
                    obscureText: true,
                    onSubmitted: (_) => _provision(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Device key',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF161A20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF5D5D), fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _provision,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6BFF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Connect kiosk',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
