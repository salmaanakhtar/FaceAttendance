import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../attendance/scan_flow.dart';
import 'scanner_screen.dart';

/// Owns the camera-backed face scanner and exposes the worker-code fallback.
class FaceGate extends StatefulWidget {
  final VoidCallback onAdminRequested;
  final VoidCallback onCodeRequested;
  const FaceGate({
    super.key,
    required this.onAdminRequested,
    required this.onCodeRequested,
  });

  @override
  State<FaceGate> createState() => _FaceGateState();
}

class _FaceGateState extends State<FaceGate> {
  ScanFlowController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final controller = ScanFlowController(cameras);
      setState(() {
        _controller = controller;
        _error = null;
      });
      await controller.init();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Camera unavailable: $error');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0D10),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error == null)
                  const CircularProgressIndicator(color: Colors.white24)
                else ...[
                  const Icon(Icons.no_photography_outlined,
                      color: Colors.white54, size: 42),
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.onCodeRequested,
                    icon: const Icon(Icons.dialpad_rounded),
                    label: const Text('Use worker code'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return ScannerScreen(
      controller: controller,
      onAdminRequested: widget.onAdminRequested,
      onCodeRequested: widget.onCodeRequested,
    );
  }
}
