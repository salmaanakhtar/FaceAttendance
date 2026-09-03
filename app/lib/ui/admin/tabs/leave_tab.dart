import 'package:flutter/material.dart';

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
import '../../../app_state.dart';
import '../../../app_time.dart';

class LeaveTab extends StatefulWidget {
  const LeaveTab({super.key});

  @override
  State<LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<LeaveTab> {
  List<LeaveEntry> _leave = [];
  List<Employee> _employees = [];
  bool _loading = true;
  bool _serverSupportsLeave = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = AppTime.now();
      final employeesResult =
          await AdminApi.instance.listEmployees(status: 'active', limit: 500);
      Map<String, dynamic> leaveResult = const {'leave': <dynamic>[]};
      var serverSupportsLeave = true;
      try {
        leaveResult = await AdminApi.instance.leaveList(
          from: '${now.year}-01-01',
          to: '${now.year + 1}-12-31',
        );
      } catch (error) {
        if (AdminApi.statusCode(error) != 404) rethrow;
        serverSupportsLeave = false;
      }
      if (!mounted) return;
      setState(() {
        _employees =
            (employeesResult['employees'] as List<dynamic>? ?? const [])
                .map((item) => Employee.fromJson(item as Map<String, dynamic>))
                .toList();
        _leave = (leaveResult['leave'] as List<dynamic>? ?? const [])
            .map((item) => LeaveEntry.fromJson(item as Map<String, dynamic>))
            .toList();
        _serverSupportsLeave = serverSupportsLeave;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load leave records: ${AdminApi.errorMessage(error)}';
      });
    }
  }

  Future<void> _openForm([LeaveEntry? entry]) async {
    AppState.instance.touchAdminActivity();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14181F),
      builder: (_) => _LeaveForm(employees: _employees, entry: entry),
    );
    if (saved == true) await _load();
  }

  Future<void> _changeStatus(LeaveEntry entry, String status) async {
    try {
      await AdminApi.instance.updateLeave(entry.id, status: status);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Leave marked $status')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = 'Could not update leave: ${AdminApi.errorMessage(error)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'all'
        ? _leave
        : _leave.where((entry) => entry.status == _filter).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Worker leave',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              FilledButton.icon(
                onPressed: !_serverSupportsLeave || _employees.isEmpty
                    ? null
                    : () => _openForm(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Record leave'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'approved', label: Text('Approved')),
                ButtonSegment(value: 'pending', label: Text('Pending')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.first),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFFF7272))),
            ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_serverSupportsLeave)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh leave records'),
                ),
              ),
            )
          else if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No leave records.',
                    style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            for (final entry in visible)
              Card(
                color: const Color(0xFF161A20),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _openForm(entry),
                  leading: Icon(
                    entry.leaveType == 'absence'
                        ? Icons.person_off_outlined
                        : entry.leaveType == 'sick'
                            ? Icons.medical_services_outlined
                            : Icons.beach_access_outlined,
                    color: _statusColor(entry.status),
                  ),
                  title: Text(entry.employeeName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${entry.typeLabel} · ${entry.dateRange}${entry.note == null ? '' : '\n${entry.note}'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  isThreeLine: entry.note != null,
                  trailing: PopupMenuButton<String>(
                    onSelected: (status) => _changeStatus(entry, status),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'approved', child: Text('Approve')),
                      PopupMenuItem(
                          value: 'pending', child: Text('Mark pending')),
                      PopupMenuItem(value: 'rejected', child: Text('Reject')),
                      PopupMenuItem(
                          value: 'cancelled', child: Text('Cancel leave')),
                    ],
                    child: Chip(
                      label: Text(entry.status),
                      backgroundColor:
                          _statusColor(entry.status).withOpacity(.16),
                      labelStyle: TextStyle(
                          color: _statusColor(entry.status), fontSize: 11),
                      side: BorderSide.none,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'approved' => const Color(0xFF2FBF71),
        'pending' => const Color(0xFFFFC857),
        'rejected' => const Color(0xFFFF7272),
        _ => Colors.white38,
      };
}

class _LeaveForm extends StatefulWidget {
  final List<Employee> employees;
  final LeaveEntry? entry;
  const _LeaveForm({required this.employees, this.entry});

  @override
  State<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends State<_LeaveForm> {
  late String _employeeId;
  late String _type;
  late String _status;
  late DateTime _start;
  late DateTime _end;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _employeeId = entry?.employeeId ?? widget.employees.first.id;
    _type = entry?.leaveType ?? 'annual';
    _status = entry?.status ?? 'approved';
    _start = DateTime.tryParse(entry?.startDate ?? '') ?? AppTime.now();
    _end = DateTime.tryParse(entry?.endDate ?? '') ?? _start;
    _note.text = entry?.note ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool start) async {
    final now = AppTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_end.isBefore(_start)) {
      setState(() => _error = 'End date must be on or after start date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.entry == null) {
        await AdminApi.instance.createLeave(
          employeeId: _employeeId,
          startDate: _date(_start),
          endDate: _date(_end),
          leaveType: _type,
          status: _status,
          note: _note.text.trim(),
        );
      } else {
        await AdminApi.instance.updateLeave(
          widget.entry!.id,
          startDate: _date(_start),
          endDate: _date(_end),
          leaveType: _type,
          status: _status,
          note: _note.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = 'Could not save leave: ${AdminApi.errorMessage(error)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.entry == null ? 'Record leave' : 'Edit leave',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _employeeId,
              dropdownColor: const Color(0xFF161A20),
              decoration: const InputDecoration(labelText: 'Worker'),
              items: [
                for (final employee in widget.employees)
                  DropdownMenuItem(
                      value: employee.id, child: Text(employee.name)),
              ],
              onChanged: widget.entry == null
                  ? (value) => setState(() => _employeeId = value!)
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              dropdownColor: const Color(0xFF161A20),
              decoration: const InputDecoration(labelText: 'Leave type'),
              items: const [
                DropdownMenuItem(value: 'annual', child: Text('Annual leave')),
                DropdownMenuItem(value: 'sick', child: Text('Sick leave')),
                DropdownMenuItem(value: 'unpaid', child: Text('Unpaid leave')),
                DropdownMenuItem(value: 'other', child: Text('Other leave')),
              ],
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _dateButton('Start', _start, () => _pick(true))),
                const SizedBox(width: 10),
                Expanded(child: _dateButton('End', _end, () => _pick(false))),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              dropdownColor: const Color(0xFF161A20),
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFFF7272))),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save leave'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateButton(String label, DateTime date, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 3),
            Text(_date(date)),
          ],
        ),
      );
}
