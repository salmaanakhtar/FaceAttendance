import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../admin/admin_api.dart';
import '../../admin/models.dart';

/// Create (or edit) an employee. Returns the created employee map on success.
class EmployeeFormSheet extends StatefulWidget {
  final Employee? employee;
  const EmployeeFormSheet({super.key, this.employee});

  @override
  State<EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<EmployeeFormSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _department = TextEditingController();
  final _hours = TextEditingController();
  final _payFields = <String, TextEditingController>{
    for (final key in [
      'hourlyRate',
      'firstName',
      'surname',
      'employerAddress',
      'identityNumber',
      'occupation',
      'startDate',
      'paymentMethod'
    ])
      key: TextEditingController(),
  };
  final Set<String> _workDays = {'mon', 'tue', 'wed', 'thu', 'fri'};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    for (final entry in _payFields.entries) {
      entry.value.text = e?.schedule[entry.key]?.toString() ??
          (entry.key == 'hourlyRate' ? '30.23' : '');
    }
    if (e != null) {
      _name.text = e.name;
      _code.text = e.employeeCode;
      _department.text = e.schedule['department']?.toString() ?? '';
      _hours.text = e.schedule['hoursPerWeek']?.toString() ?? '';
      final configured = e.schedule['workDays'];
      if (configured is List && configured.isNotEmpty) {
        _workDays
          ..clear()
          ..addAll(configured.whereType<String>());
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _department.dispose();
    _hours.dispose();
    for (final controller in _payFields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final code = _code.text.trim();
    if (widget.employee == null &&
        code.isNotEmpty &&
        !RegExp(r'^\d+$').hasMatch(code)) {
      setState(() => _error = 'Worker code must contain numbers only.');
      return;
    }
    if (_department.text.trim().isEmpty) {
      setState(() => _error = 'Department is required.');
      return;
    }
    final hours = double.tryParse(_hours.text.trim());
    if (hours == null || hours < 0 || hours > 168) {
      setState(() => _error = 'Enter weekly hours from 0 to 168.');
      return;
    }
    if (_workDays.isEmpty) {
      setState(() => _error = 'Select at least one scheduled workday.');
      return;
    }
    final schedule = <String, dynamic>{
      ...?widget.employee?.schedule,
      'department': _department.text.trim(),
      'hoursPerWeek': hours,
      'workDays': _workDays.toList(),
    };
    for (final entry in _payFields.entries) {
      final value = entry.value.text.trim();
      if (entry.key == 'hourlyRate') {
        final number = double.tryParse(value);
        if (value.isNotEmpty &&
            (number == null || !number.isFinite || number < 0)) {
          setState(() => _error = 'Enter a valid non-negative pay rate.');
          return;
        }
        schedule[entry.key] = value.isEmpty ? 30.23 : number;
      } else {
        schedule[entry.key] = value;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result;
      if (widget.employee == null) {
        result = await AdminApi.instance.createEmployee(
          name: _name.text.trim(),
          employeeCode: code,
          schedule: schedule,
        );
      } else {
        result = await AdminApi.instance.updateEmployee(
          widget.employee!.id,
          name: _name.text.trim(),
          schedule: schedule,
        );
      }
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Could not save worker: ${AdminApi.errorMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.employee != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit employee' : 'New employee',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _field(_name, 'Full name'),
            const SizedBox(height: 10),
            if (!editing) ...[
              _field(_code, 'Numeric worker code (optional)',
                  keyboard: TextInputType.number, numbersOnly: true),
              const SizedBox(height: 10),
            ],
            _field(_department, 'Department'),
            const SizedBox(height: 10),
            _field(_hours, 'Number of hours per week',
                keyboard: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Payslip details'),
              initiallyExpanded: true,
              children: [
                for (final entry in const {
                  'hourlyRate': 'Normal hourly rate (R)',
                  'firstName':
                      'Name on payslip (optional; defaults to full name)',
                  'surname': 'Surname on payslip',
                  'employerAddress': 'Employer address (optional override)',
                  'identityNumber': 'ID number',
                  'occupation': 'Occupation',
                  'startDate': 'Date engaged (YYYY-MM-DD)',
                  'paymentMethod': 'Payment method',
                }.entries)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _field(_payFields[entry.key]!, entry.value,
                          keyboard: entry.key == 'hourlyRate'
                              ? const TextInputType.numberWithOptions(
                                  decimal: true)
                              : TextInputType.text)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Scheduled workdays',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final day in const [
                  ('mon', 'M'),
                  ('tue', 'T'),
                  ('wed', 'W'),
                  ('thu', 'T'),
                  ('fri', 'F'),
                  ('sat', 'S'),
                  ('sun', 'S'),
                ])
                  FilterChip(
                    label: Text(day.$2),
                    selected: _workDays.contains(day.$1),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _workDays.add(day.$1);
                      } else {
                        _workDays.remove(day.$1);
                      }
                    }),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFFF5D5D), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F6BFF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(editing ? 'Save changes' : 'Create employee',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard, bool numbersOnly = false}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      inputFormatters: numbersOnly
          ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
          : null,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF0E1116),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    );
  }
}
