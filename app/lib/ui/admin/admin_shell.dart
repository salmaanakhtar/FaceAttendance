import 'package:flutter/material.dart';

import '../../admin/admin_api.dart';
import '../../app_state.dart';
import '../sync_status.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/audit_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/employees_tab.dart';
import 'tabs/leave_tab.dart';
import 'team_screen.dart';

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
  int _attendanceReviewSignal = 0;

  List<({IconData icon, String label})> get _tabs => [
        (icon: Icons.speed_rounded, label: 'Dashboard'),
        (icon: Icons.people_alt_outlined, label: 'Employees'),
        (icon: Icons.fact_check_outlined, label: 'Attendance'),
        (icon: Icons.beach_access_outlined, label: 'Leave'),
        if (AdminApi.instance.canManageWorkers)
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
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final content = IndexedStack(index: _tab, children: [
      DashboardTab(
          refreshSignal: _dashboardRefreshSignal,
          active: _tab == 0,
          onReviewAttendance: () => setState(() {
                _tab = 2;
                _attendanceReviewSignal++;
              })),
      const EmployeesTab(),
      AttendanceTab(reviewSignal: _attendanceReviewSignal),
      const LeaveTab(),
      if (AdminApi.instance.canManageWorkers) const AuditTab(),
    ]);
    void select(int index) {
      setState(() {
        _tab = index;
        if (index == 0) _dashboardRefreshSignal++;
      });
      AppState.instance.touchAdminActivity();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        foregroundColor: Colors.white,
        title: Text(_tabs[_tab].label),
        actions: [
          const SyncStatusButton(),
          PopupMenuButton<String>(
              tooltip: 'Account & kiosk',
              onSelected: (value) async {
                if (value == 'team') {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TeamScreen()));
                } else {
                  await AdminApi.instance.logout();
                  AppState.instance.lockToKiosk();
                }
              },
              itemBuilder: (_) => [
                    if (AdminApi.instance.canManageWorkers)
                      const PopupMenuItem(
                          value: 'team', child: Text('Team access')),
                    const PopupMenuItem(
                        value: 'lock', child: Text('Lock kiosk')),
                  ]),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final tab in _tabs)
                      NavigationRailDestination(
                          icon: Icon(tab.icon), label: Text(tab.label))
                  ]),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ])
          : content,
      floatingActionButton: _tab == 1 && AdminApi.instance.canManageWorkers
          ? const EmployeesFab()
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              backgroundColor: const Color(0xFF0E1116),
              indicatorColor: const Color(0xFF2F6BFF),
              selectedIndex: _tab,
              onDestinationSelected: select,
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(icon: Icon(t.icon), label: t.label),
              ],
            ),
    );
  }
}
