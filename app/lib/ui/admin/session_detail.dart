import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
import '../../../app_state.dart';

/// A single attendance session with manual override actions.
/// Every correction is audited server-side (old value, new value, admin,
/// reason) — raw scan events are never touched.
class SessionDetailScreen extends StatefulWidget {
  final AttendanceSession session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late AttendanceSession _session;
  List<CorrectionEntry> _corrections = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _loadCorrections();
  }

  Future<void> _loadCorrections() async {
    try {
      final res = await AdminApi.instance.corrections(sessionId: _session.id);
      if (mounted) {
        setState(() {
          _corrections = (res['corrections'] as List<dynamic>)
              .map((e) => CorrectionEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _approve() async {
    if (_busy ||
        _session.status == 'open' ||
        _session.reviewStatus == 'approved') return;
    setState(() => _busy = true);
    try {
      await AdminApi.instance.approveAttendance(_session.id);
      if (mounted)
        setState(() => _session = AttendanceSession(
            id: _session.id,
            employeeId: _session.employeeId,
            employeeName: _session.employeeName,
            employeeCode: _session.employeeCode,
            workDate: _session.workDate,
            checkInAt: _session.checkInAt,
            checkOutAt: _session.checkOutAt,
            checkInSource: _session.checkInSource,
            checkOutSource: _session.checkOutSource,
            status: _session.status,
            breakMinutes: _session.breakMinutes,
            workedMinutes: _session.workedMinutes,
            lateMinutes: _session.lateMinutes,
            earlyMinutes: _session.earlyMinutes,
            overtimeMinutes: _session.overtimeMinutes,
            isLate: _session.isLate,
            isEarly: _session.isEarly,
            hasOvertime: _session.hasOvertime,
            note: _session.note,
            corrected: _session.corrected,
            reviewStatus: 'approved',
            reviewedAt: DateTime.now().toUtc().toIso8601String()));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Timesheet approved')));
    } catch (e) {
      if (mounted) setState(() => _error = 'Approval failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correction({
    required String field,
    DateTime? initialValue,
    String? presetValue,
  }) async {
    AppState.instance.touchAdminActivity();
    DateTime? picked = initialValue;
    String? valueOverride = presetValue;
    if (field == 'check_in' ||
        field == 'check_out' ||
        field == 'add_check_in' ||
        field == 'add_check_out') {
      final now = tz.TZDateTime.now(tz.local);
      final initialLocal = initialValue == null
          ? now
          : tz.TZDateTime.from(initialValue, tz.local);
      picked = await showDatePicker(
        context: context,
        initialDate: initialLocal,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        builder: (context, child) => Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFF2F6BFF)),
          ),
          child: child!,
        ),
      );
      if (picked == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialLocal),
        builder: (context, child) => Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFF2F6BFF)),
          ),
          child: child!,
        ),
      );
      if (time == null || !mounted) return;
      picked = tz.TZDateTime(tz.local, picked.year, picked.month, picked.day,
          time.hour, time.minute);
    } else if (field == 'break_minutes') {
      final controller = TextEditingController(text: presetValue ?? '30');
      final entered = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF161A20),
          title: const Text('Edit unpaid break',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Break minutes',
                labelStyle: TextStyle(color: Colors.white54)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Next')),
          ],
        ),
      );
      if (entered == null || !mounted) return;
      valueOverride = entered;
    }

    if (!mounted) return;
    // Keep the server-side audit trail while removing the extra reason form
    // from routine manager edits.
    const reason = 'Admin timesheet edit';

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminApi.instance.applyCorrection(
        employeeId: _session.employeeId,
        // Adding a missing event targets the employee's open/incomplete
        // session server-side; passing this session ID makes the backend
        // reject the operation as an invalid add-event request.
        sessionId: field.startsWith('add_') ? null : _session.id,
        field: field,
        reason: reason,
        value: picked?.toUtc().toIso8601String() ?? valueOverride,
      );
      // Refresh the session from the server.
      final res = await AdminApi.instance.attendanceList(limit: 200);
      final fresh = (res['sessions'] as List<dynamic>)
          .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
          .where((s) => s.id == _session.id)
          .firstOrNull;
      if (fresh != null && mounted) {
        setState(() => _session = fresh);
      }
      await _loadCorrections();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correction applied and audited')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Correction failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        title: const Text('Session'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.employeeName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          Text('${s.employeeCode}  ·  ${s.workDate}  ·  ${s.status}',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timeCard('Check-in', formatLocal(s.checkInAt),
                    s.checkInSource == 'manual' ? 'manual' : null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeCard('Check-out', formatLocal(s.checkOutAt),
                    s.checkOutSource == 'manual' ? 'manual' : null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _timeCard('Worked', s.hoursText, s.corrected ? 'corrected' : null),
          const SizedBox(height: 12),
          if (s.reviewStatus == 'approved')
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_rounded, color: Color(0xFF2FBF71)),
              title: Text('Approved for payroll',
                  style: TextStyle(
                      color: Color(0xFF2FBF71), fontWeight: FontWeight.w600)),
            )
          else if (s.status == 'open')
            const Text('Open shift — add a time out before approving.',
                style: TextStyle(color: Colors.white54, fontSize: 13))
          else
            FilledButton.icon(
              onPressed: _busy ? null : _approve,
              icon: const Icon(Icons.verified_rounded),
              label: const Text('Approve timesheet'),
            ),
          const SizedBox(height: 20),
          const Text('Manual overrides',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFFF5D5D), fontSize: 13)),
            ),
          _actionButton(Icons.edit_calendar_outlined, 'Edit check-in time',
              onTap: s.checkInAt == null
                  ? null
                  : () => _correction(
                      field: 'check_in',
                      initialValue: DateTime.tryParse(s.checkInAt!)),
              enabled: !_busy),
          _actionButton(Icons.edit_calendar_outlined, 'Edit check-out time',
              onTap: s.checkOutAt == null
                  ? null
                  : () => _correction(
                      field: 'check_out',
                      initialValue: DateTime.tryParse(s.checkOutAt!)),
              enabled: !_busy),
          _actionButton(Icons.login_rounded, 'Add missing check-in',
              onTap: () => _correction(field: 'add_check_in'), enabled: !_busy),
          _actionButton(Icons.logout_rounded, 'Add missing check-out',
              onTap: () => _correction(field: 'add_check_out'),
              enabled: !_busy),
          _actionButton(Icons.free_breakfast_outlined, 'Edit unpaid break',
              onTap: () => _correction(
                  field: 'break_minutes',
                  presetValue: '${_session.breakMinutes}'),
              enabled: !_busy),
          const SizedBox(height: 20),
          const Text('Audit trail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_corrections.isEmpty)
            const Text('No corrections on this session.',
                style: TextStyle(color: Colors.white38, fontSize: 13))
          else
            for (final c in _corrections)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c.field} → ${c.newValue}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13)),
                    Text('by ${c.admin} · ${formatLocalDate(c.createdAt)}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(c.reason,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _timeCard(String label, String value, String? badge) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161A20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          if (badge != null)
            Text(badge,
                style: const TextStyle(color: Color(0xFFFFC857), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label,
      {VoidCallback? onTap, bool enabled = true}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161A20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        onTap: enabled ? onTap : null,
        leading: Icon(icon,
            color: enabled ? Colors.white70 : Colors.white24, size: 20),
        title: Text(label,
            style: TextStyle(
                color: enabled ? Colors.white70 : Colors.white24,
                fontSize: 14)),
        trailing: enabled
            ? const Icon(Icons.chevron_right_rounded, color: Colors.white24)
            : const Icon(Icons.lock_outline, color: Colors.white24, size: 16),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
