import 'dart:io';

import 'package:face_attendance/attendance/offline_queue.dart';
import 'package:face_attendance/ui/sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  testWidgets('offline pending punches remain visible and retry updates dialog',
      (tester) async {
    late Directory directory;
    late Box<String> box;
    late OfflineQueue queue;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('sync-ui-');
      Hive.init(directory.path);
      box = await Hive.openBox<String>('ui-punches');
      queue = OfflineQueue.forTesting(box, (_) async => {'action': 'check_in'});
      await queue.setOnline(false);
      await queue.enqueue(employeeId: 'worker', directionHint: 'in');
    });
    try {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SyncStatusButton(queue: queue))));
      expect(find.text('1 pending'), findsOneWidget);
      await tester.tap(find.text('1 pending'));
      await tester.pumpAndSettle();
      expect(find.text('No network connection.'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byWidgetPredicate((widget) => widget is FilledButton))
              .onPressed,
          isNull);
      await tester.runAsync(() => queue.setOnline(true));
      await tester.pumpAndSettle();
      expect(
          find.text('0 punches saved on this device, waiting for the server.'),
          findsOneWidget);
      expect(find.textContaining('Last punch delivered:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        queue.dispose();
        await box.close();
        await directory.delete(recursive: true);
      });
    }
  });
}
