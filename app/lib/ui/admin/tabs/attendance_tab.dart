import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
import '../../../app_state.dart';
import '../../../app_time.dart';
import '../../../device/secure_store.dart';
import '../session_detail.dart';
import '../payroll_screen.dart';

DateTime attendanceEntryTime(DateTime date, TimeOfDay time,
        {bool nextDay = false}) =>
    tz.TZDateTime(tz.local, date.year, date.month, date.day + (nextDay ? 1 : 0),
        time.hour, time.minute);

/// Attendance register with date range filter + CSV export.
class AttendanceTab extends StatefulWidget {
  final int reviewSignal;
  const AttendanceTab({super.key, this.reviewSignal = 0});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  List<AttendanceSession> _sessions = [];
  bool _loading = true;
  String? _error;
  DateTime? _from;
  DateTime? _to;
  String _search = '';
  bool _attentionOnly = false;
  int _loadVersion = 0;
  final _workerSearch = TextEditingController();

  @override
  void dispose() {
    _workerSearch.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _restoreRange();
  }

  Future<void> _restoreRange() async {
    final today = AppTime.now();
    _from = tz.TZDateTime(tz.local, today.year, today.month, today.day);
    _to = _from;
    try {
      final saved = await SecureStore.instance.getAttendanceRange();
      final parts = saved?.split('|');
      final from = parts == null ? null : DateTime.tryParse(parts.first);
      final to = parts == null ? null : DateTime.tryParse(parts.last);
      final now = AppTime.now();
      if (mounted &&
          from != null &&
          to != null &&
          !from.isAfter(to) &&
          !to.isAfter(now) &&
          !from.isBefore(DateTime(now.year - 2))) {
        _from = from;
        _to = to;
      }
    } catch (_) {
      // A preference read must not prevent access to attendance.
    }
    if (mounted) _load();
  }

  Future<void> _rememberRange() async {
    try {
      await SecureStore.instance.setAttendanceRange('$_fromStr|$_toStr');
    } catch (_) {
      // Keep the selected range usable when preference storage is unavailable.
    }
  }

  @override
  void didUpdateWidget(covariant AttendanceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reviewSignal != oldWidget.reviewSignal) {
      _attentionOnly = true;
      _quickRange('month');
    }
  }

  String get _fromStr => _from == null ? '' : _fmt(_from!);
  String get _toStr => _to == null ? '' : _fmt(_to!);

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    if (!mounted) return;
    final version = ++_loadVersion;
    setState(() => _loading = true);
    try {
      final res = await AdminApi.instance.allAttendance(
        from: _from == null ? null : _fmt(_from!),
        to: _to == null ? null : _fmt(_to!),
      );
      if (mounted && version == _loadVersion) {
        setState(() {
          _sessions = (res['sessions'] as List<dynamic>)
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loading = false;
          _error =
              'Could not load attendance. Check your connection and retry.';
        });
      }
    }
  }

  Future<void> _pickRange() async {
    AppState.instance.touchAdminActivity();
    final now = AppTime.now();
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
      initialDate: _to == null || _to!.isBefore(from) ? now : _to!,
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
    await _rememberRange();
    if (!mounted) return;
    _load();
  }

  Future<void> _quickRange(String period) async {
    final now = AppTime.now();
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
    await _rememberRange();
    if (!mounted) return;
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
          SnackBar(content: Text('Export failed: ${AdminApi.errorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _bulkApprove() async {
    AppState.instance.touchAdminActivity();
    if (!AdminApi.instance.canEditAttendance) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Approve completed attendance?'),
                content: Text(
                    'Approve all completed shifts for ${_from == null ? 'all dates' : '$_fromStr to $_toStr'}. Worker search and the attention filter do not limit this action. Open shifts remain unapproved.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Approve completed shifts'))
                ]));
    if (confirmed != true || !mounted) return;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Approval failed: ${AdminApi.errorMessage(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverToBoxAdapter(
            child: Column(
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                width: double.infinity,
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        AdminApi.instance.canManageWorkers ? _export : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Export CSV',
                        style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: AdminApi.instance.canManageWorkers
                        ? _exportPayslips
                        : null,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Monthly Excel & payslips',
                        style: TextStyle(fontSize: 13)),
                  ),
                  OutlinedButton.icon(
                    onPressed: AdminApi.instance.canEditAttendance
                        ? _bulkApprove
                        : null,
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
                  onPressed:
                      AdminApi.instance.canEditAttendance ? _manualEntry : null,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Add attendance'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a worker by name or code',
                    border: OutlineInputBorder()),
              ),
            ),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  FilterChip(
                      label: const Text('Needs attention'),
                      selected: _attentionOnly,
                      onSelected: (value) =>
                          setState(() => _attentionOnly = value)),
                  const Spacer(),
                  IconButton(
                      tooltip: 'Refresh attendance',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh)),
                ])),
          ],
        )),
      ],
      body: _buildBody(),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }
    if (_sessions.isEmpty) {
      return const Center(
        child: Text('No attendance in this range.',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    final visible = _sessions
        .where((s) =>
            (s.employeeName.toLowerCase().contains(_search) ||
                s.employeeCode.toLowerCase().contains(_search)) &&
            (!_attentionOnly ||
                s.status == 'incomplete' ||
                s.reviewStatus == 'needs_review'))
        .toList();
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
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _summary('Total worked', _hours(worked)),
              _summary('Overtime', _hours(overtime)),
              _summary('Open shifts', '$open'),
              _summary('Needs review', '$needsReview'),
            ],
          ),
        ),
        Text(
            '${visible.length} of ${_sessions.length} loaded shifts. Exports use the selected dates.',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        if (visible.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No shifts match your filters.')),
        for (final s in visible) _sessionTile(s),
      ],
    );
  }

  Future<void> _manualEntry() async {
    AppState.instance.touchAdminActivity();
    try {
      final employeeRes =
          await AdminApi.instance.allEmployees(status: 'active');
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
      final now = AppTime.now();
      Employee selected = employees.first;
      _workerSearch.text = '${selected.name} (${selected.employeeCode})';
      DateTime date = tz.TZDateTime(tz.local, now.year, now.month, now.day);
      TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
      TimeOfDay? end;
      bool nextDay = false;
      String? entryError;
      final values = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) =>
            StatefulBuilder(builder: (context, setDialogState) {
          String dateText() => '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}/${date.year}';
          String timeText(TimeOfDay t) => t.format(context);
          bool validWorker() {
            if (_workerSearch.text ==
                '${selected.name} (${selected.employeeCode})') return true;
            setDialogState(
                () => entryError = 'Choose a worker from the search results.');
            return false;
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF161A20),
            title: const Text('Add work time',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownMenu<Employee>(
                  controller: _workerSearch,
                  initialSelection: selected,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  width: 280,
                  label: const Text('Search worker name or code'),
                  dropdownMenuEntries: [
                    for (final e in employees)
                      DropdownMenuEntry(
                          value: e, label: '${e.name} (${e.employeeCode})')
                  ],
                  onSelected: (e) {
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
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!validWorker()) return;
                      Navigator.pop(context, {
                        'employee': selected,
                        'date': date,
                        'absent': true,
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF7272),
                      side: const BorderSide(color: Color(0xFFFF7272)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: const Icon(Icons.person_off_outlined, size: 20),
                    label: const Text('Mark absent for this date'),
                  ),
                ),
                const SizedBox(height: 10),
                _entryPickerRow(
                    context,
                    'Time in',
                    timeText(start),
                    Icons.login_rounded,
                    () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: start);
                      if (picked != null) setDialogState(() => start = picked);
                    },
                    quickLabel: 'Now',
                    quickTap: () {
                      final current = AppTime.now();
                      setDialogState(() => start = TimeOfDay(
                          hour: current.hour, minute: current.minute));
                    }),
                _entryPickerRow(
                    context,
                    'Time out (optional)',
                    end == null ? 'Skip for now' : timeText(end!),
                    Icons.logout_rounded,
                    () async {
                      final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              end ?? const TimeOfDay(hour: 17, minute: 0));
                      if (picked != null) setDialogState(() => end = picked);
                    },
                    quickLabel: 'Now',
                    quickTap: () {
                      final current = AppTime.now();
                      setDialogState(() => end = TimeOfDay(
                          hour: current.hour, minute: current.minute));
                    }),
                if (end != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Clock-out is the next day'),
                    subtitle: const Text('Select for an overnight shift.'),
                    value: nextDay,
                    onChanged: (value) =>
                        setDialogState(() => nextDay = value ?? false),
                  ),
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
                    if (!validWorker()) return;
                    final startMinutes = start.hour * 60 + start.minute;
                    final endMinutes =
                        end == null ? null : end!.hour * 60 + end!.minute;
                    if (endMinutes != null &&
                        !nextDay &&
                        endMinutes <= startMinutes) {
                      setDialogState(() => entryError =
                          'Time out must follow time in. For an overnight shift, select next day.');
                      return;
                    }
                    Navigator.pop(context, {
                      'employee': selected,
                      'date': date,
                      'start': start,
                      'end': end,
                      'nextDay': nextDay,
                    });
                  },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Review time')),
            ],
          );
        }),
      );
      if (values == null || !mounted) return;
      selected = values['employee']! as Employee;
      date = values['date']! as DateTime;
      final absent = values['absent'] == true;
      final chosenStart = values['start'] as TimeOfDay?;
      final chosenEnd = values['end'] as TimeOfDay?;
      final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(absent ? 'Confirm absence' : 'Review attendance'),
                content: Text(
                    '${selected.name} (${selected.employeeCode})\n${_fmt(date)}\n'
                    '${absent ? 'Mark absent for this date.' : 'Clock in: ${chosenStart!.format(context)}\nClock out: ${chosenEnd?.format(context) ?? 'Open shift'}${values['nextDay'] == true && chosenEnd != null ? ' (next day)' : ''}'}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm and save')),
                ],
              ));
      if (approved != true || !mounted) return;
      if (values['absent'] == true) {
        final workDate = _fmt(date);
        await AdminApi.instance.createAbsence(
          employeeId: selected.id,
          workDate: workDate,
          note: 'Recorded by admin',
        );
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${selected.name} marked absent for $workDate')));
        }
        return;
      }
      start = values['start']! as TimeOfDay;
      end = values['end'] as TimeOfDay?;
      final savedEnd = end;
      final inAt = attendanceEntryTime(date, start);
      final outAt = savedEnd == null
          ? null
          : attendanceEntryTime(date, savedEnd,
              nextDay: values['nextDay'] == true);
      // The audit record still receives a clear system reason, but the admin
      // is not required to type one for a routine manual entry.
      const reason = 'Attendance recorded by admin';
      await AdminApi.instance.createManualSession(
        employeeId: selected.id,
        checkInAt: inAt.toUtc().toIso8601String(),
        checkOutAt: outAt?.toUtc().toIso8601String(),
        reason: reason,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Attendance saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not save attendance: ${AdminApi.errorMessage(e)}')));
      }
    }
  }

  Future<void> _exportPayslips() async {
    final now = AppTime.now();
    final chosen = await showDatePicker(
        context: context,
        initialDate: _from ?? DateTime(now.year, now.month - 1, 1),
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        helpText: 'Choose any day in the payroll month');
    if (chosen == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PayrollScreen(
            from: DateTime(chosen.year, chosen.month, 1),
            to: DateTime(chosen.year, chosen.month + 1, 0))));
  }

  Widget _entryPickerRow(BuildContext context, String label, String value,
      IconData icon, VoidCallback onTap,
      {String? quickLabel, VoidCallback? quickTap}) {
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
          if (quickTap != null) ...[
            const SizedBox(width: 4),
            TextButton(
                onPressed: quickTap,
                style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(quickLabel ?? 'Now',
                    style: const TextStyle(fontSize: 12))),
          ],
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

  Widget _summary(String label, String value) => SizedBox(
        width: 110,
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
