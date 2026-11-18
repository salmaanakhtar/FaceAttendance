import 'package:dio/dio.dart';
import 'package:face_attendance/admin/admin_api.dart';
import 'package:face_attendance/admin/permissions.dart';
import 'package:face_attendance/admin/payroll_review.dart';
import 'package:face_attendance/ui/admin/review_change.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worker pagination retains search and status filters on every page',
      () async {
    final offsets = <int>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.queryParameters['search'], 'Jo');
      expect(options.queryParameters['status'], 'active');
      final offset = int.parse(options.queryParameters['offset'] as String);
      offsets.add(offset);
      handler.resolve(Response(requestOptions: options, data: {
        'employees': List.generate(
            offset == 0 ? 200 : 10, (i) => {'id': '${offset + i}'}),
        'total': 210,
      }));
    }));
    final result = await AdminApi.forTesting(dio)
        .allEmployees(search: 'Jo', status: 'active');
    expect(offsets, [0, 200]);
    expect((result['employees'] as List).length, 210);
  });
  test(
      'payroll review identifies excluded shifts, missing rates and negative pay',
      () {
    final review = PayrollReview.fromWorkers([
      {'unresolvedShifts': 2, 'rate': 30.23, 'gross': 300, 'net': -10},
      {'unresolvedShifts': 0, 'rate': null, 'gross': null},
    ], unapproved: 3);
    expect(review.unresolved, 2);
    expect(review.unapproved, 3);
    expect(review.missingRates, 1);
    expect(review.negativeNet, 1);
    expect(review.warnings.length, 4);
  });
  test(
      'roles distinguish payroll management, attendance edits and read-only access',
      () {
    expect(roleCanManage('owner'), isTrue);
    expect(roleCanManage('supervisor'), isFalse);
    expect(roleCanEditAttendance('supervisor'), isTrue);
    expect(roleCanEditAttendance('viewer'), isFalse);
    expect(
        roleAllowsRequest('viewer', 'GET', '/api/v1/admin/attendance'), isTrue);
    expect(
        roleAllowsRequest('viewer', 'POST', '/api/v1/admin/attendance/approve'),
        isFalse);
    expect(
        roleAllowsRequest('supervisor', 'POST', '/api/v1/admin/payroll/report'),
        isFalse);
    expect(roleAllowsRequest('viewer', 'GET', '/api/v1/admin/attendance-other'),
        isFalse);
  });
  test(
      'attendance totals load all server pages, including a short intermediate page',
      () async {
    final offsets = <int>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final offset = int.parse(options.queryParameters['offset'] as String);
      offsets.add(offset);
      final count = offset == 0 ? 200 : 150;
      handler.resolve(Response(requestOptions: options, data: {
        'sessions': List.generate(count, (i) => {'id': '${offset + i}'}),
        'total': 350,
      }));
    }));
    final result = await AdminApi.forTesting(dio).allAttendance();
    expect(offsets, [0, 200]);
    expect((result['sessions'] as List).length, 350);
  });
  test('incomplete pagination fails instead of returning partial totals',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options,
          data: {'sessions': <dynamic>[], 'total': 10}));
    }));
    await expectLater(
        AdminApi.forTesting(dio).allAttendance(), throwsStateError);
  });
  testWidgets(
      'correction review requires a reason and returns it only on confirmation',
      (tester) async {
    String? reason;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () async {
                        reason = await reviewAttendanceChange(context,
                            worker: 'Test Worker',
                            before: '09:00',
                            after: '08:30');
                      },
                      child: const Text('Edit'),
                    )))));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(reason, isNull);
    expect(
        find.text('Enter a reason of at least 3 characters.'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'Corrected from supervisor record');
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(reason, 'Corrected from supervisor record');
  });
}
