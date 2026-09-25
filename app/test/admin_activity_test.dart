import 'package:face_attendance/app_state.dart';
import 'package:face_attendance/config.dart';
import 'package:face_attendance/ui/admin/admin_activity_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dialog activity keeps admin open; inactivity still locks',
      (tester) async {
    final state = AppState.instance;
    state.enterAdmin();
    addTearDown(state.lockToKiosk);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AdminActivityListener(child: child!),
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: TextButton(
                          onPressed: () {}, child: const Text('Pick time')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Save'),
                        )
                      ],
                    ),
                  ),
                  child: const Text('Manual entry'),
                ),
              )),
    ));
    await tester.tap(find.text('Manual entry'));
    await tester.pumpAndSettle();
    // Work in the dialog for longer than the original three-minute deadline.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(minutes: 2));
      await tester.tap(find.text('Pick time'));
      await tester.pump();
      expect(state.adminMode, isTrue);
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.adminMode, isTrue);
    await tester.pump(kAdminInactivityLock);
    expect(state.adminMode, isFalse);
  });
}
