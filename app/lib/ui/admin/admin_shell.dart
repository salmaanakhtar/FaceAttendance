import 'package:flutter/material.dart';

import '../../admin/admin_api.dart';
import '../../app_state.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/audit_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/employees_tab.dart';
import 'tabs/leave_tab.dart';

/// Admin console: dashboard, employees, attendance, audit.
/// Auto-relocks to the scanner after [AppState] inactivity.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  int _dashboardRefreshSignal = 0;

  static const _tabs = [
    (icon: Icons.speed_rounded, label: 'Dashboard'),
    (icon: Icons.people_alt_outlined, label: 'Employees'),
    (icon: Icons.fact_check_outlined, label: 'Attendance'),
    (icon: Icons.beach_access_outlined, label: 'Leave'),
    (icon: Icons.receipt_long_outlined, label: 'Audit'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && AppState.instance.adminMode) {
      AppState.instance.lockToKiosk();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        title: Text(_tabs[_tab].label),
        actions: [
          IconButton(
            tooltip: 'Lock kiosk',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: () async {
              await AdminApi.instance.logout();
              AppState.instance.lockToKiosk();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardTab(refreshSignal: _dashboardRefreshSignal),
          const EmployeesTab(),
          const AttendanceTab(),
          const LeaveTab(),
          const AuditTab(),
        ],
      ),
      floatingActionButton: _tab == 1 ? const EmployeesFab() : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0E1116),
        indicatorColor: const Color(0xFF2F6BFF),
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() {
            _tab = i;
            if (i == 0) _dashboardRefreshSignal++;
          });
          AppState.instance.touchAdminActivity();
        },
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
