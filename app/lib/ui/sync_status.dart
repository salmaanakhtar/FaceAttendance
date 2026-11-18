import 'package:flutter/material.dart';

import '../attendance/offline_queue.dart';

/// Network availability does not prove that the attendance server is reachable.
class SyncStatusButton extends StatelessWidget {
  final OfflineQueue? queue;
  const SyncStatusButton({super.key, this.queue});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: queue ?? OfflineQueue.instance,
        builder: (context, _) {
          final queue = this.queue ?? OfflineQueue.instance;
          final pending = queue.pendingCount;
          return TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _SyncDialog(queue: queue),
            ),
            icon: Icon(pending > 0 || queue.deliveryError != null
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined),
            label: Text(pending > 0
                ? '$pending pending'
                : queue.deliveryError != null
                    ? 'Check sync'
                    : queue.online
                        ? 'Sync status'
                        : 'Offline'),
          );
        },
      );
}

class _SyncDialog extends StatelessWidget {
  final OfflineQueue queue;
  const _SyncDialog({required this.queue});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: queue,
        builder: (context, _) {
          final delivered = queue.lastDeliveredAt?.toLocal();
          final time = delivered == null
              ? 'No punches delivered during this app session.'
              : 'Last punch delivered: ${delivered.day}/${delivered.month} '
                  '${delivered.hour.toString().padLeft(2, '0')}:'
                  '${delivered.minute.toString().padLeft(2, '0')}';
          return AlertDialog(
            title: const Text('Attendance sync'),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${queue.pendingCount} punches saved on this device, waiting for the server.'),
                  const SizedBox(height: 12),
                  Text(queue.online
                      ? 'Network connection available.'
                      : 'No network connection.'),
                  const SizedBox(height: 12),
                  Text(time),
                  if (queue.deliveryError != null) ...[
                    const SizedBox(height: 12),
                    Text(queue.deliveryError!,
                        style: const TextStyle(color: Colors.amber)),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                      'Saved punches retry automatically. Keep this device connected until the pending count reaches zero.'),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
              FilledButton.icon(
                onPressed:
                    queue.syncing || !queue.online || queue.pendingCount == 0
                        ? null
                        : queue.flush,
                icon: const Icon(Icons.refresh),
                label: Text(queue.syncing ? 'Syncing…' : 'Retry now'),
              ),
            ],
          );
        },
      );
}
