import 'package:face_attendance/admin/models.dart';
import 'package:face_attendance/app_time.dart';
import 'package:face_attendance/ui/admin/session_detail.dart';
import 'package:face_attendance/ui/scanner/code_punch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  test('sanity', () {
    expect(1 + 1, 2);
  });

  test('attendance times use the organization timezone', () {
    tz.setLocalLocation(tz.getLocation('Africa/Johannesburg'));

    expect(formatLocal('2026-09-02T08:00:00.000Z'), '10:00');
    expect(formatLocalDate('2026-09-01T22:30:00.000Z'), 'Sep 2, 2026');

    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  test('live clock corrects a misconfigured device clock from server time', () {
    tz.setLocalLocation(tz.getLocation('Africa/Johannesburg'));
    AppTime.syncServerTime(
      DateTime.parse('2026-09-02T10:00:00.000Z'),
      roundTrip: const Duration(milliseconds: 200),
    );

    final corrected = AppTime.now();
    expect(corrected.year, 2026);
    expect(corrected.month, 9);
    expect(corrected.day, 2);
    expect(corrected.hour, 12);
    expect(corrected.minute, 0);
    expect(corrected.second, 0);
    AppTime.useDeviceClock();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  test('legacy Yabil timezone is corrected inside the app', () {
    AppTime.setLocal('Asia/Karachi', orgName: 'Yabil');
    AppTime.syncServerTime(DateTime.parse('2026-09-03T06:00:00.000Z'));

    final corrected = AppTime.now();
    expect(corrected.location.name, 'Africa/Johannesburg');
    expect(corrected.hour, 8);
    expect(corrected.minute, 0);

    AppTime.useDeviceClock();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  test('code punch confirmation identifies direction, worker, and time', () {
    tz.setLocalLocation(tz.getLocation('Africa/Johannesburg'));

    expect(
      punchConfirmation(
        action: 'check_in',
        employeeName: 'Test Worker',
        at: DateTime.parse('2026-09-02T08:05:00.000Z'),
        queued: false,
      ),
      'Checked in · Test Worker\nRecorded at 10:05',
    );
    expect(
      punchConfirmation(
        action: 'check_out',
        employeeName: 'Test Worker',
        at: DateTime.parse('2026-09-02T15:30:00.000Z'),
        queued: true,
      ),
      'Checked out · Test Worker\nQueued at 17:30 · saved offline',
    );

    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  testWidgets('session times are direct edit targets', (tester) async {
    final session = AttendanceSession(
      id: 'session-1',
      employeeId: 'employee-1',
      employeeName: 'Test Worker',
      employeeCode: '1001',
      workDate: '2026-09-02',
      checkInAt: '2026-09-02T08:00:00.000Z',
      checkOutAt: '2026-09-02T17:00:00.000Z',
      checkInSource: 'manual',
      checkOutSource: 'manual',
      status: 'closed',
      workedMinutes: 540,
      corrected: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: SessionDetailScreen(session: session),
    ));

    expect(find.text('Edit check-in time'), findsNothing);
    expect(find.text('Edit check-out time'), findsNothing);
    expect(find.text('Edit time'), findsNWidgets(2));
    expect(find.text('Delete time entry'), findsOneWidget);
    expect(find.text('manual'), findsNothing);
    expect(find.text('corrected'), findsNothing);

    await tester.tap(find.text('Check-in'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
