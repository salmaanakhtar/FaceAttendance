import 'package:face_attendance/admin/models.dart';
import 'package:face_attendance/ui/admin/employee_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('payslip details show saved ID and rate without expanding',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmployeeFormSheet(
      employee: Employee(
          id: 'test',
          name: 'Example Worker',
          employeeCode: '001',
          schedule: {
            'identityNumber': '0012345678901',
            'hourlyRate': 40,
            'firstName': 'Example',
            'surname': 'Worker',
          }),
    ))));
    expect(find.text('ID number'), findsOneWidget);
    expect(find.text('0012345678901'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('Example'), findsOneWidget);
    expect(find.text('Worker'), findsOneWidget);
    expect(find.textContaining('Overtime multiplier'), findsNothing);
  });

  testWidgets('new worker rate defaults to 30.23', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EmployeeFormSheet())));
    expect(find.text('30.23'), findsOneWidget);
    expect(find.text('ID number'), findsOneWidget);
  });
}
