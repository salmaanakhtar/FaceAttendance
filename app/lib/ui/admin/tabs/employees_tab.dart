import 'package:flutter/material.dart';

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';
import '../../../app_state.dart';
import '../employee_detail.dart';
import '../employee_form_sheet.dart';

/// Employee registry: search, filter, create, open details.
class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApi.instance.listEmployees(
        search: _query,
        status: _status,
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _employees = (res['employees'] as List<dynamic>)
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
          _error = 'Could not load employees: $e';
        });
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
                child: TextField(
                  onChanged: (v) {
                    _query = v;
                    _load();
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search name, code, email',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF161A20),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list_rounded, color: Colors.white70),
                onSelected: (v) {
                  _status = v;
                  _load();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All')),
                  PopupMenuItem(value: 'active', child: Text('Active')),
                  PopupMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white24));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_employees.isEmpty) {
      return const Center(
        child: Text('No employees found.',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: _employees.length,
      itemBuilder: (context, i) {
        final e = _employees[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF161A20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EmployeeDetailScreen(employee: e),
              )).then((_) => _load());
            },
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2F6BFF),
              child: Text(
                e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: Text(
              '${e.employeeCode}${e.status != 'active' ? '  ·  ${e.status}' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: e.enrolled
                ? const Icon(Icons.face_retouching_natural, color: Color(0xFF2FBF71), size: 20)
                : const Icon(Icons.face_retouching_off, color: Colors.white24, size: 20),
          ),
        );
      },
    );
  }
}

/// Floating add button lives on the shell's scaffold body — attach it here.
class EmployeesFab extends StatelessWidget {
  const EmployeesFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: const Color(0xFF2F6BFF),
      onPressed: () async {
        AppState.instance.touchAdminActivity();
        final created = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF14181F),
          builder: (_) => const EmployeeFormSheet(),
        );
        if (created != null && context.mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EmployeeDetailScreen(
              employee: Employee.fromJson(created),
            ),
          ));
        }
      },
      child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
    );
  }
}
