import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
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
  List<Employee> _employees = [];
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
      final now = tz.TZDateTime.now(tz.local);
      String date(DateTime value) =>
          '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
      final today = date(now);
      final exceptionFrom = date(now.subtract(const Duration(days: 14)));
      final nowRes = await AdminApi.instance.attendanceNow();
      final statsRes =
          await AdminApi.instance.attendanceStats(from: today, to: today);
      final periodStart = _period == 'week'
          ? now.subtract(Duration(days: now.weekday - 1))
          : tz.TZDateTime(tz.local, now.year, now.month, 1);
      final periodRes = await AdminApi.instance
          .attendanceList(from: date(periodStart), to: today, limit: 500);
      final employeeRes =
          await AdminApi.instance.listEmployees(status: 'active', limit: 500);
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
          _periodSessions = (periodRes['sessions'] as List<dynamic>? ??
                  const [])
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          _employees = (employeeRes['employees'] as List<dynamic>? ?? const [])
              .map((e) => Employee.fromJson(e as Map<String, dynamic>))
              .toList();
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
          ],
        ),
        const SizedBox(height: 18),
        Row(children: [
          const Text('Worker totals',
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
              setState(() => _period = v.first);
              _load();
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
        ({String id, String name, int minutes, int open, int expected})>{};
    for (final e in _employees) {
      totals[e.id] = (
        id: e.id,
        name: e.name,
        minutes: 0,
        open: 0,
        expected: _expectedMinutes(e)
      );
    }
    for (final s in _periodSessions) {
      final old = totals[s.employeeId];
      totals[s.employeeId] = (
        id: s.employeeId,
        name: s.employeeName,
        minutes: (old?.minutes ?? 0) + s.workedMinutes,
        open: (old?.open ?? 0) + (s.status == 'open' ? 1 : 0),
        expected: old?.expected ?? 0,
      );
    }
    if (totals.isEmpty) {
      return const _EmptyCard(
          text: 'No worker hours recorded for this period.');
    }
    final rows = totals.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Column(children: [
      for (final row in rows)
        Card(
            color: const Color(0xFF161A20),
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
                dense: false,
                onTap: () => _showWorkerSessions(row.id, row.name),
                title: Row(children: [
                  Expanded(
                      child: Text(row.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500))),
                  Text(_fmtHours(row.minutes),
                      style: const TextStyle(
                          color: Color(0xFF4DA3FF),
                          fontWeight: FontWeight.w700)),
                ]),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            row.minutes == 0 && row.open == 0
                                ? 'No hours recorded'
                                : row.open == 0
                                    ? 'Complete shifts'
                                    : '${row.open} open shift${row.open == 1 ? '' : 's'}',
                            style: const TextStyle(color: Colors.white38)),
                        if (row.expected > 0) ...[
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              value:
                                  (row.minutes / row.expected).clamp(0.0, 1.0),
                              backgroundColor: Colors.white12,
                              color: const Color(0xFF2FBF71),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text('of ${_fmtHours(row.expected)} planned',
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 11)),
                        ],
                      ]),
                ),
                trailing: const Icon(Icons.edit_outlined,
                    size: 18, color: Colors.white38)))
    ]);
  }

  int _expectedMinutes(Employee employee) {
    final raw = employee.schedule['hoursPerWeek'];
    final weekly = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    if (weekly <= 0) return 0;
    if (_period == 'week') return (weekly * 60).round();
    final now = tz.TZDateTime.now(tz.local);
    final days = DateTime(now.year, now.month + 1, 0).day;
    return (weekly * 60 * days / 7).round();
  }

  Future<void> _showWorkerSessions(String employeeId, String name) async {
    final sessions = _periodSessions
        .where((s) => s.employeeId == employeeId)
        .toList()
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
                    subtitle: Text(
                        '${formatLocal(s.checkInAt)} → ${formatLocal(s.checkOutAt)}',
                        style: const TextStyle(color: Colors.white54)),
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
    return Row(
      children: [
        for (final s in stats)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
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
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ),
      ],
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
