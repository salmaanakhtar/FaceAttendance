import 'package:flutter/material.dart';

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';

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
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    if (e != null) {
      _name.text = e.name;
      _code.text = e.employeeCode;
      _email.text = e.email ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
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
          employeeCode: _code.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        );
      } else {
        result = await AdminApi.instance.updateEmployee(
          widget.employee!.id,
          name: _name.text.trim(),
          email: _email.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      setState(() => _error = 'Save failed: $e');
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(editing ? 'Edit employee' : 'New employee',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _field(_name, 'Full name'),
          const SizedBox(height: 10),
          if (!editing) ...[
            _field(_code, 'Employee code (optional)'),
            const SizedBox(height: 10),
          ],
          _field(_email, 'Email (optional)', keyboard: TextInputType.emailAddress),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF5D5D), fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2F6BFF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(editing ? 'Save changes' : 'Create employee',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF0E1116),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }
}
