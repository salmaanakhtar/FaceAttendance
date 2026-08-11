import 'package:flutter/material.dart';

import '../../admin/admin_api.dart';
import '../../admin/models.dart';
import '../../app_state.dart';
import '../enrollment/enrollment_screen.dart';
import 'employee_form_sheet.dart';

/// Employee profile: info, edit, lifecycle, enrollment, recent attendance,
/// correction history.
class EmployeeDetailScreen extends StatefulWidget {
  final Employee employee;
  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late Employee _employee;
  List<AttendanceSession> _sessions = [];
  List<CorrectionEntry> _corrections = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final emp = await AdminApi.instance.getEmployee(_employee.id);
      final att = await AdminApi.instance.attendanceEmployee(_employee.id);
      final corr = await AdminApi.instance.corrections(employeeId: _employee.id);
      if (mounted) {
        setState(() {
          _employee = Employee.fromJson(emp);
          _sessions = (att['sessions'] as List<dynamic>)
              .map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>))
              .toList()
              .take(10)
              .toList();
          _corrections = (corr['corrections'] as List<dynamic>)
              .map((e) => CorrectionEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load employee: $e';
        });
      }
    }
  }

  Future<void> _edit() async {
    AppState.instance.touchAdminActivity();
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14181F),
      builder: (_) => EmployeeFormSheet(employee: _employee),
    );
    if (updated != null) {
      setState(() => _employee = Employee.fromJson(updated));
    }
  }

  Future<void> _deactivate() async {
    AppState.instance.touchAdminActivity();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161A20),
        title: const Text('Deactivate employee?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '${_employee.name} will no longer be able to check in.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Deactivate', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm == true) {
      await AdminApi.instance.deactivateEmployee(_employee.id);
      if (mounted) {
        setState(() => _employee = Employee.fromJson(
            {..._employee.toJson(), 'status': 'inactive'}));
      }
    }
  }

  Future<void> _enroll() async {
    AppState.instance.touchAdminActivity();
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EnrollmentScreen(employeeId: _employee.id),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        title: const Text('Employee'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white24))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFF2F6BFF),
                          child: Text(
                            _employee.name.isNotEmpty ? _employee.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_employee.name,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                              Text(
                                '${_employee.employeeCode}  ·  ${_employee.status}',
                                style: const TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                              if (_employee.email != null)
                                Text(_employee.email!,
                                    style: const TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _enroll,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2F6BFF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.face_retouching_natural, color: Colors.white),
                      label: Text(
                        _employee.enrolled ? 'Re-enroll face' : 'Enroll face',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_employee.enrolled) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text('Enrolled ${formatLocalDate(_employee.enrolledAt)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _sectionTitle('Recent attendance'),
                    if (_sessions.isEmpty)
                      const _Empty(text: 'No sessions yet.')
                    else
                      for (final s in _sessions)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161A20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${formatLocal(s.checkInAt)} → ${formatLocal(s.checkOutAt)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                              ),
                              Text('${s.workedMinutes ~/ 60}h ${s.workedMinutes % 60}m',
                                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
                              if (s.isLate)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.schedule_rounded,
                                      color: Color(0xFFFFC857), size: 16),
                                ),
                              if (s.status == 'open')
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.circle, color: Color(0xFF2FBF71), size: 10),
                                ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 16),
                    _sectionTitle('Corrections'),
                    if (_corrections.isEmpty)
                      const _Empty(text: 'No corrections recorded.')
                    else
                      for (final c in _corrections)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161A20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c.field}  ·  ${formatLocalDate(c.createdAt)}  ·  by ${c.admin}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(c.reason,
                                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                    const SizedBox(height: 20),
                    if (_employee.status == 'active')
                      OutlinedButton.icon(
                        onPressed: _deactivate,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF5D5D),
                          side: const BorderSide(color: Color(0x55FF5D5D)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.block_rounded, size: 18),
                        label: const Text('Deactivate employee'),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    );
  }
}
