import 'package:face_attendance/ui/admin/tabs/attendance_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUp(() {
    data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Johannesburg'));
  });

  test('overnight entry rolls into next month in organization timezone', () {
    final date = DateTime(2026, 11, 30);
    final start =
        attendanceEntryTime(date, const TimeOfDay(hour: 22, minute: 0));
    final end = attendanceEntryTime(date, const TimeOfDay(hour: 6, minute: 0),
        nextDay: true);
    expect(end.toUtc(), DateTime.utc(2026, 12, 1, 4));
    expect(end.difference(start), const Duration(hours: 8));
  });

  test('normal entry keeps the chosen work date', () {
    final time = attendanceEntryTime(
        DateTime(2026, 11, 18), const TimeOfDay(hour: 9, minute: 30));
    expect(time.toUtc(), DateTime.utc(2026, 11, 18, 7, 30));
  });
}
