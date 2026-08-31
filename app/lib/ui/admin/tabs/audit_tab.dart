import 'package:flutter/material.dart';

import '../../../admin/admin_api.dart';
import '../../../admin/models.dart';

/// Audit log: who did what, when.
class AuditTab extends StatefulWidget {
  const AuditTab({super.key});

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  List<AuditEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApi.instance.auditLog();
      if (mounted) {
        setState(() {
          _events = (res['events'] as List<dynamic>)
              .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load audit log: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white24));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)));
    }
    if (_events.isEmpty) {
      return const Center(
        child: Text('No audit events yet.', style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, i) {
        final e = _events[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161A20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                e.actorType == 'device'
                    ? Icons.devices_rounded
                    : e.actorType == 'admin'
                        ? Icons.person_rounded
                        : Icons.settings_rounded,
                color: Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.action, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    if (e.targetType != null)
                      Text('${e.targetType}${e.targetId == null ? '' : ' · ${e.targetId}'}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    if (e.details != null && e.details!.isNotEmpty)
                      Text(e.details.toString(), style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Text(formatLocal(e.createdAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
