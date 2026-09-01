import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 2),
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${result['approved'] ?? 0} completed shift(s) approved')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Approval failed: $e')));
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Create an active worker first')));
        return;
      }
      Employee selected = employees.first;
      final chosen = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  backgroundColor: const Color(0xFF161A20),
                  title: const Text('Manual time entry',
                      style: TextStyle(color: Colors.white, fontSize: 17)),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<Employee>(
                      value: selected,
                      dropdownColor: const Color(0xFF20252D),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'Worker',
                          labelStyle: TextStyle(color: Colors.white54)),
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
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Choose times')),
                  ],
                )),
      );
      if (chosen != true || !mounted) return;
      final now = DateTime.now();
      final date = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(now.year - 2),
          lastDate: now);
      if (date == null || !mounted) return;
      final start = await showTimePicker(
          context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
      if (start == null || !mounted) return;
      final addCheckout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF161A20),
          title: const Text('Add time out?',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: const Text(
              'You can leave this shift open and add the time out later.',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip for now')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Choose time out')),
          ],
        ),
      );
      if (addCheckout == null || !mounted) return;
      TimeOfDay? end;
      if (addCheckout) {
        end = await showTimePicker(
            context: context,
            initialTime: const TimeOfDay(hour: 17, minute: 0));
        if (end == null || !mounted) return;
      }
      final inAt =
          DateTime(date.year, date.month, date.day, start.hour, start.minute);
      final outAt = end == null
          ? null
          : DateTime(date.year, date.month, date.day, end.hour, end.minute);
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Manual time entry saved and audited')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Manual entry failed: $e')));
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Payroll report failed: $e')));
    }
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
