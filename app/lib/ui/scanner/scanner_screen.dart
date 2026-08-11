import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../attendance/scan_flow.dart';
import '../../device/secure_store.dart';
import '../../app_state.dart';
import '../../updater/update_state.dart';

/// The kiosk's primary surface: live camera + scan state feedback.
/// Everything else (admin) is behind the lock icon.
class ScannerScreen extends StatefulWidget {
  final ScanFlowController controller;
  final VoidCallback onAdminRequested;
  const ScannerScreen({super.key, required this.controller, required this.onAdminRequested});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  String _orgName = '';
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _loadOrg();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _loadOrg() async {
    final name = await SecureStore.instance.getOrgName();
    if (mounted && name != null) setState(() => _orgName = name);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CameraLayer(controller: widget.controller),
            _StatusOverlay(controller: widget.controller),
            _TopBar(orgName: _orgName, onAdmin: widget.onAdminRequested),
            _OfflineBadge(controller: widget.controller),
            const _UpdateBanner(),
          ],
        ),
      ),
    );
  }
}

class _CameraLayer extends StatelessWidget {
  final ScanFlowController controller;
  const _CameraLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final camera = controller.camera;
        if (camera == null || !camera.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        }
        return CameraPreview(camera);
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final String orgName;
  final VoidCallback onAdmin;
  const _TopBar({required this.orgName, required this.onAdmin});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 0),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  orgName.isEmpty ? 'FaceAttendance' : orgName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                _Clock(),
              ],
            ),
            const Spacer(),
            // Lock — the only admin entry point.
            Material(
              color: Colors.black38,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAdmin,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final date = '${_month(now.month)} ${now.day}, ${now.year}';
    return Text(
      '$time  ·  $date',
      style: const TextStyle(color: Colors.white54, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
    );
  }

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  String _month(int m) => _months[m - 1];
}

class _OfflineBadge extends StatelessWidget {
  final ScanFlowController controller;
  const _OfflineBadge({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final queued = controller.lastSyncWasOffline;
        final offline = !AppState.instance.online;
        if (!offline && !queued) return const SizedBox.shrink();
        return Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3A2E14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFC857), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    queued ? 'Scan queued — will sync when back online' : 'Offline — scanning works, syncing later',
                    style: const TextStyle(color: Color(0xFFFFC857), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  final ScanFlowController controller;
  const _StatusOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final outcome = controller.outcome;

        // During a result hold, show the outcome card.
        if (outcome != null) {
          return _ResultCard(outcome: outcome);
        }
        return _PromptBanner(phase: phase);
      },
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateState.instance,
      builder: (context, _) {
        final s = UpdateState.instance;
        switch (s.phase) {
          case UpdatePhase.available:
            return Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: _pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.system_update_alt_rounded, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Update ${s.info?.latest ?? ''} available',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      _tapTarget('Install', onTap: s.downloadAndInstall),
                    ],
                  ),
                ),
              ),
            );
          case UpdatePhase.downloading:
            return Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: _pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Downloading ${(s.progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            );
          case UpdatePhase.downloaded:
            return Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: _pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_done_rounded, color: Color(0xFF2FBF71), size: 18),
                      const SizedBox(width: 8),
                      const Text('Ready to install', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(width: 10),
                      _tapTarget('Install now', onTap: UpdateState.instance.downloadAndInstall),
                    ],
                  ),
                ),
              ),
            );
          case UpdatePhase.error:
            return Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: _pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5D5D), size: 18),
                      const SizedBox(width: 8),
                      Text('Update failed — ${s.error}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(width: 10),
                      _tapTarget('Retry', onTap: () {
                        UpdateState.instance.dismiss();
                        UpdateState.instance.check();
                      }),
                    ],
                  ),
                ),
              ),
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _pill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEE161A20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _tapTarget(String label, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2F6BFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _PromptBanner extends StatelessWidget {
  final ScanPhase phase;
  const _PromptBanner({required this.phase});

  String get _title {
    switch (phase) {
      case ScanPhase.init:
        return 'Starting scanner…';
      case ScanPhase.idle:
        return 'Look at the camera';
      case ScanPhase.faceDetected:
        return 'Hold still…';
      case ScanPhase.scanning:
        return 'Scanning…';
      case ScanPhase.faceTooFar:
        return 'Move closer to the camera';
      case ScanPhase.poorLighting:
        return 'Lighting too low — please face the light';
      case ScanPhase.multipleFaces:
        return 'Only one person at a time, please';
      case ScanPhase.unknown:
        return 'Face not recognized — ask an admin to enroll you';
      case ScanPhase.ambiguous:
        return 'Unclear match — try again or ask an admin';
      case ScanPhase.livenessFailed:
        return 'Look at the camera and blink naturally';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _title;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xE60B0D10)],
            stops: [0.0, 0.55],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (phase == ScanPhase.scanning || phase == ScanPhase.faceDetected)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70),
                ),
              ),
            Flexible(
              child: Text(
                t,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScanOutcome outcome;
  const _ResultCard({required this.outcome});

  (IconData, Color, String, String) get _content {
    switch (outcome.phase) {
      case ScanPhase.checkIn:
        return (Icons.login_rounded, const Color(0xFF2FBF71), 'Checked in', outcome.employeeName ?? '');
      case ScanPhase.checkOut:
        return (Icons.logout_rounded, const Color(0xFF4DA3FF), 'Checked out', outcome.employeeName ?? '');
      case ScanPhase.duplicate:
        return (Icons.touch_app_rounded, const Color(0xFFFFC857), 'Already recorded', outcome.message ?? '');
      case ScanPhase.alreadyIn:
        return (Icons.check_circle_outline_rounded, const Color(0xFFFFC857), 'Already checked in', outcome.employeeName ?? '');
      case ScanPhase.alreadyOut:
        return (Icons.radio_button_checked_rounded, const Color(0xFFFFC857), 'Already checked out', outcome.employeeName ?? '');
      case ScanPhase.backendFailure:
        return (Icons.error_outline_rounded, const Color(0xFFFF5D5D), 'Server error', 'Please try again');
      default:
        return (Icons.error_outline_rounded, const Color(0xFFFF5D5D), 'Scan error', 'Please try again');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = _content;
    final time = outcome.at != null
        ? '${outcome.at!.hour.toString().padLeft(2, '0')}:${outcome.at!.minute.toString().padLeft(2, '0')}:${outcome.at!.second.toString().padLeft(2, '0')}'
        : null;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xF20E1116),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.55), width: 1.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500),
              ),
            ],
            if (time != null) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: const TextStyle(color: Colors.white54, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
            if (outcome.score != null) ...[
              const SizedBox(height: 2),
              Text(
                'match ${(outcome.score! * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
