import 'dart:async';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:face_attendance/attendance/offline_queue.dart';
import 'package:face_attendance/device/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed sync retains punches and successful retry clears warning',
      () async {
    final directory = await Directory.systemTemp.createTemp('sync-retry-');
    Hive.init(directory.path);
    final box = await Hive.openBox<String>('retry-punches');
    var fail = true;
    final keys = <String>[];
    final queue = OfflineQueue.forTesting(box, (scan) async {
      keys.add(scan.dedupeKey);
      if (fail) throw ServerException(403, {});
      return {'action': 'check_in'};
    });
    try {
      await expectLater(
          queue.enqueue(employeeId: 'worker', directionHint: 'in'),
          throwsA(isA<ServerException>()));
      expect(queue.pendingCount, 1);
      expect(queue.deliveryError, contains('Device access'));
      expect(queue.lastDeliveredAt, isNull);
      await queue.flush();
      expect(queue.pendingCount, 1);
      expect(queue.syncing, isFalse);
      fail = false;
      await queue.flush();
      expect(queue.pendingCount, 0);
      expect(queue.deliveryError, isNull);
      expect(queue.lastDeliveredAt, isNotNull);
      expect(keys.toSet().length, 1);
    } finally {
      queue.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });

  test('network available with unreachable server is shown as pending',
      () async {
    final directory = await Directory.systemTemp.createTemp('sync-offline-');
    Hive.init(directory.path);
    final box = await Hive.openBox<String>('offline-punches');
    final queue = OfflineQueue.forTesting(
        box, (_) async => throw OfflineException('timeout'));
    try {
      final result =
          await queue.enqueue(employeeId: 'worker', directionHint: 'in');
      expect(result['queued'], isTrue);
      expect(queue.online, isTrue);
      expect(queue.deliveryError, contains('Server unreachable'));
      expect(queue.pendingCount, 1);
      await queue.flush();
      expect(queue.pendingCount, 1);
      expect(queue.syncing, isFalse);
    } finally {
      queue.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });
  test('offline clock-out stays separate and follows its queued clock-in',
      () async {
    final directory = await Directory.systemTemp.createTemp('punch-order-');
    Hive.init(directory.path);
    final box = await Hive.openBox<String>('punches');
    final delivered = <PendingScan>[];
    final queue = OfflineQueue.forTesting(box, (scan) async {
      delivered.add(scan);
      return {'action': scan.directionHint == 'out' ? 'check_out' : 'check_in'};
    });
    try {
      queue.setOnline(false);
      final sameTime = DateTime.utc(2026, 11, 18, 8);
      await queue.enqueue(
          employeeId: 'worker', directionHint: 'in', deviceTime: sameTime);
      await queue.enqueue(
          employeeId: 'worker', directionHint: 'out', deviceTime: sameTime);
      await queue.enqueue(employeeId: 'worker', directionHint: 'out');
      expect(queue.pendingCount, 2);
      queue.setOnline(true);
      final result =
          await queue.enqueue(employeeId: 'worker', directionHint: 'out');
      expect(result['action'], 'check_out');
      expect(delivered.map((scan) => scan.directionHint), ['in', 'out']);
      expect(delivered.map((scan) => scan.dedupeKey).toSet().length, 2);
      expect(queue.pendingCount, 0);
    } finally {
      queue.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  });

  test('concurrent retries share one request per idempotency key', () async {
    final gate = ScanDeliveryGate();
    final response = Completer<Map<String, dynamic>>();
    var requests = 0;

    Future<Map<String, dynamic>> deliver() {
      requests++;
      return response.future;
    }

    final foreground = gate.run('punch-1', deliver);
    final background = gate.run('punch-1', deliver);

    expect(identical(foreground, background), isTrue);
    expect(requests, 1);

    response.complete({'action': 'check_in'});
    expect(await foreground, {'action': 'check_in'});
    expect(await background, {'action': 'check_in'});
  });
}
