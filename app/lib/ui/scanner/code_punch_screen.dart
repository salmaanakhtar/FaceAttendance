import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app_state.dart';
import '../../app_time.dart';
import '../../attendance/offline_queue.dart';
import '../../device/api.dart';
import '../../device/secure_store.dart';
import '../../recognition/matcher.dart';
import '../../recognition/template_store.dart';
import '../../util/feedback.dart';

String punchConfirmation({
  required String action,
  required String employeeName,
  required DateTime at,
  required bool queued,
}) {
  final local = tz.TZDateTime.from(at, tz.local);
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final label = action == 'check_out' ? 'Checked out' : 'Checked in';
  final timeLabel =
      queued ? 'Queued at $time · saved offline' : 'Recorded at $time';
  return '$label · $employeeName\n$timeLabel';
}

String punchFailureMessage(String action, String? serverMessage) {
  if (action == 'duplicate') {
    return 'Punch already recorded. Please wait one minute before trying again.';
  }
  return serverMessage ?? 'Already recorded.';
}

class CodePunchScreen extends StatefulWidget {
  final VoidCallback onAdminRequested;
  const CodePunchScreen({super.key, required this.onAdminRequested});

  @override
  State<CodePunchScreen> createState() => _CodePunchScreenState();
}

class _CodePunchScreenState extends State<CodePunchScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  List<_KioskEmployee> _employees = [];
  Timer? _clock;
  String _orgName = '';
  String? _error;
  String? _message;
  bool _loading = true;
  bool _busy = false;
  bool _keyboardMode = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final org = await SecureStore.instance.getOrgName();
      final res = await ApiClient.instance
          .fetchEmployees()
          .timeout(const Duration(seconds: 3));
      final raw = (res['employees'] as List<dynamic>? ?? const []);
      await SecureStore.instance.setKioskRoster(jsonEncode(raw));
      if (mounted) {
        setState(() {
          _orgName = org ?? '';
          _employees = raw
              .map((e) => _KioskEmployee.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      // Keep the last authenticated roster available during WAN outages so
      // code punching remains usable offline; attendance events still queue
      // and retain idempotency until delivery.
      try {
        final cached = await SecureStore.instance.getKioskRoster();
        final raw = cached == null
            ? const <dynamic>[]
            : jsonDecode(cached) as List<dynamic>;
        if (mounted && raw.isNotEmpty) {
          setState(() {
            _employees = raw
                .map((e) => _KioskEmployee.fromJson(e as Map<String, dynamic>))
                .toList();
            _loading = false;
            _error = null;
          });
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Worker list unavailable. Check connection and retry.';
        });
      }
    }
  }

  Future<void> _submit([String? rawCode]) async {
    if (_busy) return;
    final value = (rawCode ?? _code.text).trim();
    if (value.isEmpty) {
      setState(() {
        _error = 'Enter your worker code.';
        _message = null;
      });
      _showPunchBanner('Enter your worker code.', success: false);
      return;
    }
    final employee = _employees.cast<_KioskEmployee?>().firstWhere(
          (e) => e!.code.toLowerCase() == value.toLowerCase(),
          orElse: () => null,
        );
    if (employee == null) {
      setState(() {
        _error = 'Code not found. Check the code and try again.';
        _message = null;
      });
      _showPunchBanner(_error!, success: false);
      await FeedbackFx.error();
      _code.clear();
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final direction = hintDirection(
      lastDirection: StatusCache.instance.lastDirection(employee.id),
      isCurrentlyIn: StatusCache.instance.isIn(employee.id),
    );
    try {
      final result = await OfflineQueue.instance.enqueue(
        employeeId: employee.id,
        directionHint: direction,
      );
      final queued = result['queued'] == true;
      final action = result['action'] as String? ??
          (direction == 'out' ? 'check_out' : 'check_in');
      final at = DateTime.tryParse(result['scanTime'] as String? ?? '') ??
          AppTime.now();
      if (action == 'duplicate' ||
          action == 'already_in' ||
          action == 'already_out') {
        final message =
            punchFailureMessage(action, result['message'] as String?);
        if (!mounted) return;
        setState(() => _error = message);
        _showPunchBanner(message, success: false);
        await FeedbackFx.error();
      } else {
        StatusCache.instance.recordOutcome(employee.id, action, at);
        final message = punchConfirmation(
          action: action,
          employeeName: employee.name,
          at: at,
          queued: queued,
        );
        if (!mounted) return;
        setState(() => _message = message);
        _showPunchBanner(
          message,
          success: true,
          checkedOut: action == 'check_out',
        );
        await FeedbackFx.success();
        unawaited(FeedbackFx.speak(action == 'check_out'
            ? 'Goodbye ${employee.name}'
            : 'Welcome ${employee.name}'));
      }
      _code.clear();
      _focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      const message = 'Could not save punch. Try again.';
      setState(() => _error = message);
      _showPunchBanner(message, success: false);
      await FeedbackFx.error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPunchBanner(
    String message, {
    required bool success,
    bool checkedOut = false,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        backgroundColor: success
            ? (checkedOut ? const Color(0xFF174A78) : const Color(0xFF17623D))
            : const Color(0xFF722E35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(
              success
                  ? (checkedOut ? Icons.logout_rounded : Icons.login_rounded)
                  : Icons.info_outline_rounded,
              color: Colors.white,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.35),
              ),
            ),
          ],
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final now = AppTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      body: SafeArea(
        child: Stack(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_orgName.isEmpty ? 'FaceAttendance' : _orgName,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(time,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 13)),
                    ])),
                IconButton(
                    tooltip: 'Refresh worker codes',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70)),
                IconButton(
                    tooltip: 'Admin',
                    onPressed: widget.onAdminRequested,
                    icon: const Icon(Icons.lock_outline_rounded,
                        color: Colors.white70)),
              ]),
              const SizedBox(height: 70),
              const Icon(Icons.pin_outlined,
                  color: Color(0xFF4DA3FF), size: 54),
              const SizedBox(height: 18),
              const Text('Enter your worker code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                  'Press Enter or tap Punch. The first punch checks you in; the next checks you out.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 28),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('WORKER CODE',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                focusNode: _focus,
                enabled: !_busy,
                readOnly: !_keyboardMode,
                keyboardType: _keyboardMode
                    ? TextInputType.visiblePassword
                    : TextInputType.none,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'WORKER CODE',
                  hintStyle: const TextStyle(
                      color: Colors.white24, fontSize: 16, letterSpacing: 1),
                  filled: true,
                  fillColor: const Color(0xFF161A20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  suffixIcon: IconButton(
                    tooltip: _keyboardMode
                        ? 'Use number keypad'
                        : 'Enter letters with keyboard',
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _keyboardMode = !_keyboardMode);
                            if (_keyboardMode) _focus.requestFocus();
                          },
                    icon: Icon(
                        _keyboardMode
                            ? Icons.dialpad_rounded
                            : Icons.keyboard_alt_outlined,
                        color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _numberKeypad(),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _keyboardMode = !_keyboardMode);
                        if (_keyboardMode) _focus.requestFocus();
                      },
                icon: Icon(_keyboardMode
                    ? Icons.dialpad_rounded
                    : Icons.keyboard_alt_outlined),
                label: Text(_keyboardMode
                    ? 'Use number keypad'
                    : 'Use keyboard for letter codes'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.login_rounded),
                    label: Text(_busy ? 'Saving…' : 'Punch time',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  )),
              if (_loading) ...[
                const SizedBox(height: 20),
                const Center(
                    child: CircularProgressIndicator(color: Colors.white24))
              ],
              if (_error != null) ...[
                const SizedBox(height: 20),
                _notice(_error!, false)
              ],
              if (_message != null) ...[
                const SizedBox(height: 20),
                _notice(_message!, true)
              ],
              if (_employees.isEmpty && !_loading && _error == null) ...[
                const SizedBox(height: 20),
                _notice('No active worker codes are available.', false),
              ],
            ],
          ),
          Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: ListenableBuilder(
                  listenable: AppState.instance,
                  builder: (context, _) => ListenableBuilder(
                      listenable: OfflineQueue.instance,
                      builder: (context, _) {
                        final pending = OfflineQueue.instance.pendingCount;
                        if (AppState.instance.online && pending == 0) {
                          return const SizedBox.shrink();
                        }
                        return Center(
                            child: Text(
                                pending > 0
                                    ? '$pending punch${pending == 1 ? '' : 'es'} waiting to sync'
                                    : 'Offline — punches will sync later',
                                style: const TextStyle(
                                    color: Color(0xFFFFC857), fontSize: 12)));
                      })))
        ]),
      ),
    );
  }

  Widget _numberKeypad() {
    final keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'Clear',
      '0',
      '⌫'
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.25,
      children: [
        for (final key in keys)
          OutlinedButton(
            onPressed: _busy
                ? null
                : () {
                    if (key == 'Clear') {
                      _code.clear();
                    } else if (key == '⌫') {
                      if (_code.text.isNotEmpty) {
                        _code.text =
                            _code.text.substring(0, _code.text.length - 1);
                      }
                    } else {
                      _code.text = '${_code.text}$key';
                    }
                    _focus.requestFocus();
                    setState(() {
                      _error = null;
                      _message = null;
                    });
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              backgroundColor: const Color(0xFF161A20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: TextStyle(
                  fontSize: key == 'Clear' ? 13 : 22,
                  fontWeight: FontWeight.w600),
            ),
            child: Text(key),
          ),
      ],
    );
  }

  Widget _notice(String text, bool success) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: success ? const Color(0x2230BF71) : const Color(0x22FF5D5D),
            borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(success ? Icons.check_circle_outline : Icons.info_outline,
              color:
                  success ? const Color(0xFF2FBF71) : const Color(0xFFFF7272),
              size: 20),
          const SizedBox(width: 8),
          Flexible(
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: success
                          ? const Color(0xFF8FE0B1)
                          : const Color(0xFFFFA0A0),
                      fontSize: 14))),
        ]),
      );
}

class _KioskEmployee {
  final String id;
  final String name;
  final String code;
  const _KioskEmployee(
      {required this.id, required this.name, required this.code});
  factory _KioskEmployee.fromJson(Map<String, dynamic> j) => _KioskEmployee(
      id: j['id'] as String,
      name: j['name'] as String,
      code: j['employeeCode'] as String);
}
