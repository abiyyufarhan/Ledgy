import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_backdrop.dart';
import '../router/app_router.dart';
import '../features/security/presentation/app_lock_gate.dart';

class LedgyApp extends StatelessWidget {
  LedgyApp({super.key, this.initialLocation})
    : _router = createAppRouter(initialLocation: initialLocation);

  final String? initialLocation;
  final GoRouter _router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ledgy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
      builder: (context, child) =>
          AppBackdrop(child: AppLockGate(child: child ?? const SizedBox())),
    );
  }
}
