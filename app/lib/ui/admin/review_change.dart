import 'package:flutter/material.dart';

Future<String?> reviewAttendanceChange(
  BuildContext context, {
  required String worker,
  required String before,
  required String after,
  bool removing = false,
}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _ChangeReview(
            worker: worker, before: before, after: after, removing: removing));

class _ChangeReview extends StatefulWidget {
  final String worker, before, after;
  final bool removing;
  const _ChangeReview(
      {required this.worker,
      required this.before,
      required this.after,
      required this.removing});
  @override
  State<_ChangeReview> createState() => _ChangeReviewState();
}

class _ChangeReviewState extends State<_ChangeReview> {
  final _reason = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.removing ? 'Review removal' : 'Review attendance change'),
        content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(widget.worker,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('Before', style: TextStyle(color: Colors.white70)),
              Text(widget.before),
              const SizedBox(height: 12),
              const Text('After', style: TextStyle(color: Colors.white70)),
              Text(widget.after),
              const SizedBox(height: 12),
              TextField(
                  controller: _reason,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                      labelText: 'Reason for this change',
                      hintText: 'For example: worker forgot to clock out',
                      errorText: _error)),
              const Text(
                  'Your name, reason and change will be recorded in the audit history.'),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final reason = _reason.text.trim();
                if (reason.length < 3) {
                  setState(() =>
                      _error = 'Enter a reason of at least 3 characters.');
                  return;
                }
                Navigator.pop(context, reason);
              },
              child:
                  Text(widget.removing ? 'Confirm removal' : 'Confirm change')),
        ],
      );
}
