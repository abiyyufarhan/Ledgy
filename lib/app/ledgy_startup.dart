import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/branding/ledgy_mark.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/data/cloud_connection.dart';
import '../features/local/presentation/local_automation_host.dart';
import '../features/sync/presentation/sync_host.dart';
import '../features/sync/presentation/sync_providers.dart';
import 'ledgy_app.dart';

/// Render a private, lightweight splash while initialization is in progress.
/// No artificial delay and no transaction/account data in this screen.
class LedgyStartup extends StatefulWidget {
  const LedgyStartup({super.key, this.initialize});
  final Future<CloudConnection> Function()? initialize;

  @override
  State<LedgyStartup> createState() => _LedgyStartupState();
}

class _LedgyStartupState extends State<LedgyStartup> {
  late Future<CloudConnection> _startup;

  Future<CloudConnection> _initialize() async {
    await initializeDateFormatting('id_ID');
    return CloudConnection.initialize();
  }

  @override
  void initState() {
    super.initState();
    _startup = (widget.initialize ?? _initialize)();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CloudConnection>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [
            cloudConnectionProvider.overrideWithValue(snapshot.data!),
          ],
          child: SyncHost(child: LocalAutomationHost(child: LedgyApp())),
        );
      }
      return MaterialApp(
        title: 'Ledgy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: LedgySplash(
          failed:
              snapshot.connectionState == ConnectionState.done &&
              snapshot.hasError,
          onRetry: () => setState(() {
            _startup = (widget.initialize ?? _initialize)();
          }),
        ),
      );
    },
  );
}

class LedgySplash extends StatelessWidget {
  const LedgySplash({super.key, this.failed = false, this.onRetry});
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LedgyBrand.background,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LedgyMark(),
              const SizedBox(height: AppTheme.sectionSpacing),
              Text('Ledgy', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: AppTheme.compactSpacing),
              const Text(
                'Keuangan pribadi, lebih teratur.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.sectionSpacing),
              if (failed) ...[
                const Text(
                  'Aplikasi belum dapat disiapkan.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.fieldSpacing),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi'),
                ),
              ] else
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
