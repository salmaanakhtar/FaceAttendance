import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../admin/admin_api.dart';
import '../../admin/models.dart';
import '../../app_time.dart';
import 'employee_form_sheet.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.from, required this.to});
  final DateTime from;
  final DateTime to;
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  Map<String, dynamic>? _report;
  String? _error;
  bool _busy = false;
  final Map<String, Map<String, dynamic>> _adjustments = {};
  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Map<String, dynamic> get _body => {
        'from': _date(widget.from),
        'to': _date(widget.to),
        'adjustments': _adjustments.values.toList(),
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report =
          await AdminApi.instance.post('/api/v1/admin/payroll/report', _body);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) setState(() => _error = AdminApi.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editRates(Map<String, dynamic> worker) async {
    final employee = Employee(
        id: worker['id'] as String,
        employeeCode: worker['code'] as String,
        name: worker['name'] as String,
        schedule: Map<String, dynamic>.from(worker['schedule'] as Map));
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => EmployeeFormSheet(employee: employee));
    if (saved != null && mounted) await _load();
  }

  Future<void> _editAdjustments(Map<String, dynamic> worker) async {
    const labels = {
      'holidayPay': 'Holiday pay (R)',
      'otherPay': 'Other earnings (R)',
      'uif': 'UIF deduction (R)',
      'otherDeductions': 'Other deductions (R)'
    };
    final controllers = {
      for (final key in labels.keys)
        key: TextEditingController(text: '${worker[key] ?? 0}')
    };
    String? error;
    final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text('${worker['name']} · Pay adjustments'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Amounts apply to this export period. No deduction is calculated automatically.'),
                    for (final entry in labels.entries)
                      TextField(
                          controller: controllers[entry.key],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(labelText: entry.value)),
                    if (error != null)
                      Text(error!,
                          style: const TextStyle(color: Colors.redAccent)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          final values = <String, dynamic>{
                            'employeeId': worker['id']
                          };
                          for (final entry in controllers.entries) {
                            final n = double.tryParse(entry.value.text);
                            if (n == null || !n.isFinite || n < 0 || n > 1e9) {
                              update(() =>
                                  error = 'Enter valid non-negative amounts.');
                              return;
                            }
                            values[entry.key] = n;
                          }
                          Navigator.pop(context, values);
                        },
                        child: const Text('Apply'))
                  ],
                )));
    // Dialog removal animations may still reference controllers until the next frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controllers.values) {
      c.dispose();
    }
    if (values != null && mounted) {
      _adjustments[worker['id'] as String] = values;
      await _load();
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await AdminApi.instance.exportPayroll(_body);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/payroll-${_date(widget.from)}-${_date(widget.to)}-${AppTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ], subject: 'Monthly hours and payslips');
    } catch (e) {
      if (mounted) setState(() => _error = AdminApi.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(dynamic value) =>
      value == null ? 'Set rate' : 'R ${(value as num).toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) {
    final workers =
        (_report?['workers'] as List? ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly payroll')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${_date(widget.from)} to ${_date(widget.to)}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            'Excel includes a worker-hours summary, individual payslips below it, and an All times sheet.'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed:
                _busy || _report == null || _error != null ? null : _export,
            icon: const Icon(Icons.download),
            label: const Text('Export Excel workbook')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          TextButton(
              onPressed: _busy ? null : _load, child: const Text('Retry'))
        ],
        const SizedBox(height: 12),
        const Text(
            'Pay adjustments are kept while this report is open. Save the Excel file to retain them.'),
        for (final worker in workers)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(worker['name'] as String,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                            '${((worker['workedMinutes'] as num) / 60).toStringAsFixed(2)} hours · '
                            'Gross ${_money(worker['gross'])} · Net ${_money(worker['net'])}'),
                        if ((worker['unresolvedShifts'] as num) > 0)
                          Text(
                              '${worker['unresolvedShifts']} unresolved shifts excluded',
                              style:
                                  const TextStyle(color: Colors.orangeAccent)),
                        if (worker['gross'] == null)
                          const Text('Set pay rates before payment.',
                              style: TextStyle(color: Colors.orangeAccent)),
                        Wrap(spacing: 8, children: [
                          TextButton.icon(
                              onPressed:
                                  _busy ? null : () => _editRates(worker),
                              icon: const Icon(Icons.edit),
                              label: const Text('Pay rates & details')),
                          TextButton.icon(
                              onPressed:
                                  _busy ? null : () => _editAdjustments(worker),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Earnings & deductions')),
                        ]),
                      ]))),
        if (!_busy && _report != null && workers.isEmpty)
          const Text('No workers in this period.'),
      ]),
    );
  }
}
