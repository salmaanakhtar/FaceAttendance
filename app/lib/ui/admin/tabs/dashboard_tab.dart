import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
import '../../../app_time.dart';
import '../session_detail.dart';

/// Live operations snapshot: who is in right now + today's numbers.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<AttendanceSession> _now = [];
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _exceptions = [];
  List<AttendanceSession> _periodSessions = [];
  List<AttendanceSession> _weekSessions = [];
  List<AttendanceSession> _daySessions = [];
  List<AttendanceSession> _monthSessions = [];
  List<Employee> _employees = [];
  Map<String, Map<String, dynamic>> _weekAbsence = {};
  Map<String, Map<String, dynamic>> _monthAbsence = {};
  int _monthAbsentDays = 0;
  String _period = 'week';
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll =
        Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final now = AppTime.now();
      String date(DateTime value) =>
          '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
      final today = date(now);
      final exceptionFrom = date(now.subtract(const Duration(days: 14)));
      final nowRes = await AdminApi.instance.attendanceNow();
      final statsRes =
          await AdminApi.instance.attendanceStats(from: today, to: today);
      final monthStart = tz.TZDateTime(tz.local, now.year, now.month, 1);
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final results = await Future.wait([
        AdminApi.instance.attendanceList(from: today, to: today, limit: 500),
        AdminApi.instance
            .attendanceList(from: date(weekStart), to: today, limit: 500),
        AdminApi.instance
            .attendanceList(from: date(monthStart), to: today, limit: 500),
      ]);
      final employeeRes =
          await AdminApi.instance.listEmployees(status: 'active', limit: 500);
      Map<String, dynamic> weekAbsenceRes = const {'workers': <dynamic>[]};
      Map<String, dynamic> monthAbsenceRes = const {'workers': <dynamic>[]};
      try {
        final absenceResults = await Future.wait([
          AdminApi.instance.absenceSummary(from: date(weekStart), to: today),
          AdminApi.instance.absenceSummary(from: date(monthStart), to: today),
        ]);
        weekAbsenceRes = absenceResults[0];
        monthAbsenceRes = absenceResults[1];
      } catch (_) {
        // Leave/absence may not be deployed yet during a rolling upgrade.
      }
      // Older servers do not expose the exception inbox yet. Keep the rest of
      // the dashboard usable during a rolling app/backend deployment.
      Map<String, dynamic> exceptionRes = const {'exceptions': <dynamic>[]};
      try {
        exceptionRes = await AdminApi.instance
            .attendanceExceptions(from: exceptionFrom, to: today, limit: 20);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _now = (nowRes['currentlyIn'] as List<dynamic>)
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _stats = statsRes['aggregate'] as Map<String, dynamic>?;
          _exceptions =
              (exceptionRes['exceptions'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>();
          _daySessions = (results[0]['sessions'] as List<dynamic>? ?? const [])
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _weekSessions = (results[1]['sessions'] as List<dynamic>? ?? const [])
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _monthSessions = (results[2]['sessions'] as List<dynamic>? ??
                  const [])
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _periodSessions = _period == 'week' ? _weekSessions : _monthSessions;
          _employees = (employeeRes['employees'] as List<dynamic>? ?? const [])
              .map((e) => Employee.fromJson(e as Map<String, dynamic>))
              .toList();
          _weekAbsence = {
            for (final worker
                in (weekAbsenceRes['workers'] as List<dynamic>? ?? const []))
              (worker as Map<String, dynamic>)['employeeId'] as String: worker,
          };
          _monthAbsence = {
            for (final worker
                in (monthAbsenceRes['workers'] as List<dynamic>? ?? const []))
              (worker as Map<String, dynamic>)['employeeId'] as String: worker,
          };
          _monthAbsentDays =
              (monthAbsenceRes['totalAbsentDays'] as num?)?.toInt() ?? 0;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load dashboard: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white24));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final agg = _stats ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatRow(
          stats: [
            (
              label: 'Currently in',
              value: '${_now.length}',
              color: const Color(0xFF2FBF71)
            ),
            (
              label: 'Today sessions',
              value: '${agg['sessions'] ?? 0}',
              color: const Color(0xFF4DA3FF)
            ),
            (
              label: 'Late',
              value: '${agg['lateCount'] ?? 0}',
              color: const Color(0xFFFFC857)
            ),
            (
              label: 'Incomplete',
              value: '${agg['incompleteCount'] ?? 0}',
              color: const Color(0xFFFF5D5D)
            ),
            (
              label: 'Absent this month',
              value: '$_monthAbsentDays',
              color: const Color(0xFFFF7272)
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(children: [
          const Text('Working hours',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'week', label: Text('Week')),
              ButtonSegment(value: 'month', label: Text('Month')),
            ],
            selected: {_period},
            onSelectionChanged: (v) {
              setState(() {
                _period = v.first;
                _periodSessions =
                    _period == 'week' ? _weekSessions : _monthSessions;
              });
            },
          ),
        ]),
        const SizedBox(height: 8),
        _workerTotals(),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('In right now',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
                'worked today ${_fmtHours((agg['workedMinutes'] as num?)?.toInt() ?? 0)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        if (_now.isEmpty)
          const _EmptyCard(text: 'No one is checked in right now.')
        else
          for (final s in _now)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF161A20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded,
                      color: Color(0xFF2FBF71), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s.employeeName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                  ),
                  Text(formatLocal(s.checkInAt),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('Needs attention',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${_exceptions.length} exceptions',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        if (_exceptions.isEmpty)
          const _EmptyCard(text: 'No attendance exceptions in this period.')
        else
          for (final issue in _exceptions.take(6)) _exceptionCard(issue),
      ],
    );
  }

  Widget _workerTotals() {
    final totals = <String,
        ({
      String id,
      String name,
      int day,
      int week,
      int month,
      int open,
      int expected,
      int weekAbsent,
      int weekLeave,
      int monthAbsent,
      int monthLeave
    })>{};
    for (final e in _employees) {
      totals[e.id] = (
        id: e.id,
        name: e.name,
        day: 0,
        week: 0,
        month: 0,
        open: 0,
        expected: _expectedMinutes(e),
        weekAbsent: (_weekAbsence[e.id]?['absentDays'] as num?)?.toInt() ?? 0,
        weekLeave: (_weekAbsence[e.id]?['leaveDays'] as num?)?.toInt() ?? 0,
        monthAbsent: (_monthAbsence[e.id]?['absentDays'] as num?)?.toInt() ?? 0,
        monthLeave: (_monthAbsence[e.id]?['leaveDays'] as num?)?.toInt() ?? 0
      );
    }
    void add(List<AttendanceSession> sessions, String field) {
      for (final s in sessions) {
        final old = totals[s.employeeId];
        totals[s.employeeId] = (
          id: s.employeeId,
          name: s.employeeName,
          day: field == 'day'
              ? (old?.day ?? 0) + s.workedMinutes
              : (old?.day ?? 0),
          week: field == 'week'
              ? (old?.week ?? 0) + s.workedMinutes
              : (old?.week ?? 0),
          month: field == 'month'
              ? (old?.month ?? 0) + s.workedMinutes
              : (old?.month ?? 0),
          open: (old?.open ?? 0) + (s.status == 'open' ? 1 : 0),
          expected: old?.expected ?? 0,
          weekAbsent: old?.weekAbsent ?? 0,
          weekLeave: old?.weekLeave ?? 0,
          monthAbsent: old?.monthAbsent ?? 0,
          monthLeave: old?.monthLeave ?? 0,
        );
      }
    }

    add(_daySessions, 'day');
    add(_periodSessions, 'week');
    add(_monthSessions, 'month');
    if (totals.isEmpty) {
      return const _EmptyCard(
          text: 'No worker hours recorded for this period.');
    }
    final rows = totals.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Card(
      color: const Color(0xFF161A20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStatePropertyAll(Colors.white.withOpacity(.04)),
          columns: const [
            DataColumn(label: Text('Worker')),
            DataColumn(label: Text('Today')),
            DataColumn(label: Text('This week')),
            DataColumn(label: Text('This month')),
            DataColumn(label: Text('Week status')),
            DataColumn(label: Text('Month status')),
          ],
          rows: [
            for (final row in rows)
              DataRow(cells: [
                DataCell(
                    Text(row.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    onTap: () => _showWorkerSessions(row.id, row.name)),
                DataCell(
                    Text(_fmtHours(row.day),
                        style: const TextStyle(color: Colors.white70)),
                    onTap: () => _showWorkerSessions(row.id, row.name)),
                DataCell(
                    Text(_fmtHours(row.week),
                        style: const TextStyle(
                            color: Color(0xFF4DA3FF),
                            fontWeight: FontWeight.w700)),
                    onTap: () => _showWorkerSessions(row.id, row.name)),
                DataCell(
                    Text(_fmtHours(row.month),
                        style: const TextStyle(
                            color: Color(0xFF2FBF71),
                            fontWeight: FontWeight.w700)),
                    onTap: () => _showWorkerSessions(row.id, row.name)),
                DataCell(Text(
                  '${row.weekAbsent} absent\n${row.weekLeave} leave',
                  style: TextStyle(
                    color: row.weekAbsent > 0
                        ? const Color(0xFFFF7272)
                        : Colors.white54,
                    fontSize: 12,
                  ),
                )),
                DataCell(Text(
                  '${row.monthAbsent} absent\n${row.monthLeave} leave',
                  style: TextStyle(
                    color: row.monthAbsent > 0
                        ? const Color(0xFFFF7272)
                        : Colors.white54,
                    fontSize: 12,
                  ),
                )),
              ])
          ],
        ),
      ),
    );
  }

  int _expectedMinutes(Employee employee) {
    final raw = employee.schedule['hoursPerWeek'];
    final weekly = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    if (weekly <= 0) return 0;
    if (_period == 'week') return (weekly * 60).round();
    final now = AppTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;
    return (weekly * 60 * days / 7).round();
  }

  Future<void> _showWorkerSessions(String employeeId, String name) async {
    final source = _period == 'week' ? _weekSessions : _monthSessions;
    final sessions = source.where((s) => s.employeeId == employeeId).toList()
      ..sort((a, b) => b.workDate.compareTo(a.workDate));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161A20),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text(
                    '$name · ${_period == 'week' ? 'This week' : 'This month'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
              ),
              Text('${sessions.length} shift${sessions.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white54)),
            ]),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white12),
                itemBuilder: (_, index) {
                  final s = sessions[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        s.status == 'open'
                            ? Icons.radio_button_checked
                            : Icons.event_available_outlined,
                        color: s.status == 'open'
                            ? const Color(0xFF2FBF71)
                            : Colors.white54),
                    title: Text(s.workDate,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _editableSessionTime(
                          sheetContext: sheetContext,
                          session: s,
                          field: 'check_in',
                          value: formatLocal(s.checkInAt),
                        ),
                        const Text(' → ',
                            style: TextStyle(color: Colors.white38)),
                        _editableSessionTime(
                          sheetContext: sheetContext,
                          session: s,
                          field: 'check_out',
                          value: formatLocal(s.checkOutAt),
                        ),
                      ],
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(s.hoursText,
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined,
                          size: 18, color: Colors.white54),
                    ]),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => SessionDetailScreen(session: s)))
                          .then((_) => _load(silent: true));
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _editableSessionTime({
    required BuildContext sheetContext,
    required AttendanceSession session,
    required String field,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        Navigator.pop(sheetContext);
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => SessionDetailScreen(
                      session: session,
                      initialEditField: field,
                    )))
            .then((_) => _load(silent: true));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Text(value,
            style: const TextStyle(
                color: Color(0xFF7EA2FF),
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline)),
      ),
    );
  }

  Widget _exceptionCard(Map<String, dynamic> issue) {
    final session =
        AttendanceSession.fromJson(issue['session'] as Map<String, dynamic>);
    final type = issue['type'] as String? ?? 'exception';
    final minutes = (issue['minutes'] as num?)?.toInt();
    final label = switch (type) {
      'missed_checkout' => 'Missing clock-out',
      'late_arrival' => 'Late arrival',
      'early_departure' => 'Early departure',
      'overtime' => 'Overtime',
      _ => 'Attendance exception',
    };
    final high = issue['severity'] == 'high';
    return Card(
      color: const Color(0xFF161A20),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: session)))
            .then((_) => _load(silent: true)),
        leading: Icon(
            high ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
            color: high ? const Color(0xFFFF5D5D) : const Color(0xFFFFC857)),
        title: Text(session.employeeName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(
            '$label${minutes == null ? '' : ' · $minutes min'} · ${session.workDate}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
      ),
    );
  }

  String _fmtHours(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';
}

class _StatRow extends StatelessWidget {
  final List<({String label, String value, Color color})> stats;
  const _StatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520 ? 2 : stats.length;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in stats)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161A20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(s.value,
                          style: TextStyle(
                              color: s.color,
                              fontSize: 24,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(s.label,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161A20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 13)),
    );
  }
}
