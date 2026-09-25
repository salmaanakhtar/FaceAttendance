import 'package:flutter/material.dart';

import '../../app_state.dart';

/// Wrap the navigator so dialogs, pickers and pushed pages count as activity.
class AdminActivityListener extends StatelessWidget {
  const AdminActivityListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => AppState.instance.touchAdminActivity(),
        onPointerMove: (_) => AppState.instance.touchAdminActivity(),
        onPointerSignal: (_) => AppState.instance.touchAdminActivity(),
        child: child,
      );
}
