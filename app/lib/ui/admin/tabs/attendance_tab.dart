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

  Future<void> _export() async {
    AppState.instance.touchAdminActivity();
    try {
      final csv = await AdminApi.instance.exportCsv(
        from: _from == null ? null : _fmt(_from!),
        to: _to == null ? null : _fmt(_to!),
      );
      final dir = await getTemporaryDirectory();
      final file = '${dir.path}/attendance-${DateTime.now().millisecondsSinceEpoch}.csv';
      await File(file).writeAsString(csv);
      await SharePlus.instance.share(ShareParams(files: [XFile(file)], subject: 'Attendance export'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export CSV', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white24));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)));
    }
    if (_sessions.isEmpty) {
      return const Center(
        child: Text('No attendance in this range.',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _sessions.length,
      itemBuilder: (context, i) {
        final s = _sessions[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF161A20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: s),
              )).then((_) => _load());
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
      },
    );
  }
}
