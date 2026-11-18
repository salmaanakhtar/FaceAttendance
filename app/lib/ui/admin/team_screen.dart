import 'package:flutter/material.dart';
import '../../admin/admin_api.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _busy = false;
  String? _error;
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
      final result = await AdminApi.instance.get('/api/v1/admin/team');
      if (mounted) {
        setState(() => _members =
            (result['members'] as List).cast<Map<String, dynamic>>());
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AdminApi.statusCode(error) == 404
            ? 'Team access requires the updated backend. Install its migration and release first.'
            : AdminApi.errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final values = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _NewMemberDialog());
    if (values == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await AdminApi.instance.post('/api/v1/admin/team', values);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = AdminApi.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> member) async {
    final active = member['active'] != true;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title:
                    Text('${active ? 'Enable' : 'Disable'} ${member['name']}?'),
                content: const Text(
                    'Changing access is recorded in the audit history. Disabled accounts cannot make further requests.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AdminApi.instance
          .patch('/api/v1/admin/team/${member['id']}', {'active': active});
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = AdminApi.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Team access')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Administrators manage workers and payroll. Supervisors manage attendance and leave. Viewers can read operational records. Payroll and team management are restricted to administrators.'),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _busy || _error != null ? null : _create,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add limited account')),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.amber)),
            TextButton(
                onPressed: _busy ? null : _load, child: const Text('Retry'))
          ],
          for (final member in _members)
            Card(
                child: ListTile(
              title: Text('${member['name']}'),
              subtitle: Text(
                  '${member['username']} · ${member['role']} · ${member['active'] == true ? 'Active' : 'Disabled'}'),
              trailing: ['supervisor', 'viewer'].contains(member['role'])
                  ? TextButton(
                      onPressed: _busy ? null : () => _toggle(member),
                      child:
                          Text(member['active'] == true ? 'Disable' : 'Enable'))
                  : null,
            )),
        ]),
      );
}

class _NewMemberDialog extends StatefulWidget {
  const _NewMemberDialog();
  @override
  State<_NewMemberDialog> createState() => _NewMemberDialogState();
}

class _NewMemberDialogState extends State<_NewMemberDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController();
  String _role = 'viewer';
  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add limited account'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      controller: _name,
                      maxLength: 200,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Enter a name.'
                          : null),
                  TextFormField(
                      controller: _username,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Username'),
                      validator: (value) => RegExp(r'^[a-zA-Z0-9._-]{3,100}$')
                              .hasMatch(value ?? '')
                          ? null
                          : 'Use at least 3 letters, numbers, dots, hyphens or underscores.'),
                  TextFormField(
                      controller: _password,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      maxLength: 200,
                      decoration: const InputDecoration(
                          labelText: 'Password (12+ characters)'),
                      validator: (value) => (value ?? '').length < 12
                          ? 'Use at least 12 characters.'
                          : null),
                  DropdownButtonFormField<String>(
                      value: _role,
                      decoration: const InputDecoration(labelText: 'Access'),
                      items: const [
                        DropdownMenuItem(
                            value: 'viewer', child: Text('Viewer — read only')),
                        DropdownMenuItem(
                            value: 'supervisor',
                            child: Text('Supervisor — attendance & leave'))
                      ],
                      onChanged: (value) => setState(() => _role = value!)),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, {
                    'name': _name.text.trim(),
                    'username': _username.text.trim(),
                    'password': _password.text,
                    'role': _role
                  });
                }
              },
              child: const Text('Create account'))
        ],
      );
}
