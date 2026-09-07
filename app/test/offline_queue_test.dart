import 'dart:async';

import 'package:face_attendance/attendance/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
