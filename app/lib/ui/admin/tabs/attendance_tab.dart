import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
import '../../../app_state.dart';
import '../session_detail.dart';

/// Attendance register with date range filter + CSV export.
class AttendanceTab extends StatefulWidget {
  const AttendanceTab({super.key});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  List<AttendanceSession> _sessions = [];
  bool _loading = true;
  String? _error;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _fromStr => _from == null ? '' : _fmt(_from!);
  String get _toStr => _to == null ? '' : _fmt(_to!);

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApi.instance.attendanceList(
        from: _from == null ? null : _fmt(_from!),
        to: _to == null ? null : _fmt(_to!),
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _sessions = (res['sessions'] as List<dynamic>)
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load attendance: $e';
        });
      }
    }
  }

  Future<void> _pickRange() async {
    AppState.instance.touchAdminActivity();
    final now = tz.TZDateTime.now(tz.local);
    final from = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: tz.TZDateTime(tz.local, now.year - 2),
      lastDate: now,
      builder: (context, child) => Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF2F6BFF)),
        ),
        child: child!,
      ),
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: from,
      lastDate: now,
      builder: (context, child) => Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF2F6BFF)),
        ),
        child: child!,
      ),
    );
    if (to == null || !mounted) return;
    setState(() {
      _from = from;
      _to = to;
    });
    _load();
  }

  void _quickRange(String period) {
    final now = tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    final from = period == 'today'
        ? today
        : period == 'week'
            ? today.subtract(Duration(days: today.weekday - 1))
            : DateTime(today.year, today.month, 1);
    setState(() {
      _from = from;
      _to = today;
    });
    _load();
  }

  Future<void> _export() async {
    AppState.instance.touchAdminActivity();
    try {
      final csv = await AdminApi.instance.exportCsv(
        from: _from == null ? null : _fmt(_from!),
        to: _to == null ? null : _fmt(_to!),
      );
      final dir = await getTemporaryDirectory();
      final file =
          '${dir.path}/attendance-${DateTime.now().millisecondsSinceEpoch}.csv';
      await File(file).writeAsString(csv);
      await Share.shareXFiles([XFile(file)], subject: 'Attendance export');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _bulkApprove() async {
    AppState.instance.touchAdminActivity();
    try {
      final result = await AdminApi.instance.bulkApproveAttendance(
        from: _from == null ? null : _fmt(_from!),
        to: _to == null ? null : _fmt(_to!),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${result['approved'] ?? 0} completed shift(s) approved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Approval failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              children: [
                _quickChip('Today', 'today'),
                _quickChip('This week', 'week'),
                _quickChip('This month', 'month'),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(
                    _from == null ? 'All dates' : '$_fromStr → $_toStr',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _export,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export CSV', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _exportPayslips,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Pay report', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _bulkApprove,
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Approve completed',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _manualEntry,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Manual time entry'),
            ),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _quickChip(String label, String period) =>
      ActionChip(label: Text(label), onPressed: () => _quickRange(period));

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white24));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white54)));
    }
    if (_sessions.isEmpty) {
      return const Center(
        child: Text('No attendance in this range.',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    final worked = _sessions.fold<int>(0, (sum, s) => sum + s.workedMinutes);
    final overtime =
        _sessions.fold<int>(0, (sum, s) => sum + s.overtimeMinutes);
    final open = _sessions.where((s) => s.status == 'open').length;
    final needsReview = _sessions
        .where((s) => s.reviewStatus == 'needs_review' && s.status != 'open')
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161A20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _summary('Total worked', _hours(worked)),
              _summary('Overtime', _hours(overtime)),
              _summary('Open shifts', '$open'),
              _summary('Needs review', '$needsReview'),
            ],
          ),
        ),
        for (final s in _sessions) _sessionTile(s),
      ],
    );
  }

  Future<void> _manualEntry() async {
    AppState.instance.touchAdminActivity();
    try {
      final employeeRes =
          await AdminApi.instance.listEmployees(status: 'active', limit: 500);
      final employees = (employeeRes['employees'] as List<dynamic>)
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || employees.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Create an active worker first')));
        }
        return;
      }
      final now = tz.TZDateTime.now(tz.local);
      Employee selected = employees.first;
      DateTime date = tz.TZDateTime(tz.local, now.year, now.month, now.day);
      TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
      TimeOfDay? end;
      String? entryError;
      final values = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) =>
            StatefulBuilder(builder: (context, setDialogState) {
          String dateText() => '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}/${date.year}';
          String timeText(TimeOfDay t) => t.format(context);
          return AlertDialog(
            backgroundColor: const Color(0xFF161A20),
            title: const Text('Add work time',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<Employee>(
                  value: selected,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF20252D),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Worker'),
                  items: [
                    for (final e in employees)
                      DropdownMenuItem(
                          value: e,
                          child: Text('${e.name} (${e.employeeCode})'))
                  ],
                  onChanged: (e) {
                    if (e != null) setDialogState(() => selected = e);
                  },
                ),
                const SizedBox(height: 10),
                _entryPickerRow(context, 'Work date', dateText(), Icons.event,
                    () async {
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: tz.TZDateTime(tz.local, now.year - 2),
                      lastDate: now);
                  if (picked != null) setDialogState(() => date = picked);
                }),
                _entryPickerRow(
                    context, 'Time in', timeText(start), Icons.login_rounded,
                    () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: start);
                  if (picked != null) setDialogState(() => start = picked);
                }),
                _entryPickerRow(
                    context,
                    'Time out (optional)',
                    end == null ? 'Skip for now' : timeText(end!),
                    Icons.logout_rounded, () async {
                  final picked = await showTimePicker(
                      context: context,
                      initialTime: end ?? const TimeOfDay(hour: 17, minute: 0));
                  if (picked != null) setDialogState(() => end = picked);
                }),
                if (end != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: () => setDialogState(() => end = null),
                        child: const Text('Skip time out')),
                  ),
                const SizedBox(height: 4),
                if (entryError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(entryError!,
                        style: const TextStyle(
                            color: Color(0xFFFF7272), fontSize: 12)),
                  ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Leave time out blank for an open shift.',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton.icon(
                  onPressed: () {
                    final startMinutes = start.hour * 60 + start.minute;
                    final endMinutes =
                        end == null ? null : end!.hour * 60 + end!.minute;
                    if (endMinutes != null && endMinutes <= startMinutes) {
                      setDialogState(() => entryError =
                          'Time out must be later than time in (same day).');
                      return;
                    }
                    Navigator.pop(context, {
                      'employee': selected,
                      'date': date,
                      'start': start,
                      'end': end,
                    });
                  },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save time')),
            ],
          );
        }),
      );
      if (values == null || !mounted) return;
      selected = values['employee']! as Employee;
      date = values['date']! as DateTime;
      start = values['start']! as TimeOfDay;
      end = values['end'] as TimeOfDay?;
      final savedEnd = end;
      final inAt = tz.TZDateTime(
          tz.local, date.year, date.month, date.day, start.hour, start.minute);
      final outAt = savedEnd == null
          ? null
          : tz.TZDateTime(tz.local, date.year, date.month, date.day,
              savedEnd.hour, savedEnd.minute);
      // The audit record still receives a clear system reason, but the admin
      // is not required to type one for a routine manual entry.
      const reason = 'Manual time entry';
      await AdminApi.instance.applyCorrection(
          employeeId: selected.id,
          field: 'add_check_in',
          reason: reason,
          value: inAt.toUtc().toIso8601String());
      if (outAt != null) {
        await AdminApi.instance.applyCorrection(
            employeeId: selected.id,
            field: 'add_check_out',
            reason: reason,
            value: outAt.toUtc().toIso8601String());
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Manual time entry saved and audited')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Manual entry failed: $e')));
      }
    }
  }

  Future<void> _exportPayslips() async {
    if (_from == null || _to == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose a date range for the payroll report')));
      return;
    }
    try {
      final csv = await AdminApi.instance
          .exportPayslipEstimate(from: _fmt(_from!), to: _fmt(_to!));
      final dir = await getTemporaryDirectory();
      final file =
          '${dir.path}/payslip-estimate-${DateTime.now().millisecondsSinceEpoch}.csv';
      await File(file).writeAsString(csv);
      await Share.shareXFiles([XFile(file)], subject: 'Payslip estimate');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Payroll report failed: $e')));
      }
    }
  }

  Widget _entryPickerRow(BuildContext context, String label, String value,
      IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 19, color: const Color(0xFF8FAEFF)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 14))),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 5),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: Colors.white38),
        ]),
      ),
    );
  }

  Widget _sessionTile(AttendanceSession s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161A20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: s),
              ))
              .then((_) => _load());
        },
        title: Text(s.employeeName,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        subtitle: Text(
          '${formatLocal(s.checkInAt)} → ${formatLocal(s.checkOutAt)}',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(s.hoursText,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (s.status == 'open')
              const Text('● in',
                  style: TextStyle(color: Color(0xFF2FBF71), fontSize: 11))
            else if (s.reviewStatus == 'needs_review')
              const Text('needs review',
                  style: TextStyle(color: Color(0xFFFFC857), fontSize: 11))
            else if (s.status == 'incomplete')
              const Text('incomplete',
                  style: TextStyle(color: Color(0xFFFFC857), fontSize: 11))
            else if (s.isLate)
              const Text('late',
                  style: TextStyle(color: Color(0xFFFFC857), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _summary(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  String _hours(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';
}
