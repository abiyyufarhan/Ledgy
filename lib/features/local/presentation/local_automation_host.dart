import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:workmanager/workmanager.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../data/local_finance_repository.dart';
import '../data/local_notifications.dart';
import 'local_providers.dart';

@pragma('vm:entry-point')
void ledgyBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDatabase();
    try {
      final finance = LocalFinanceRepository(db);
      await finance.generateDue(DateTime.now());
      await finance.checkBudgets(DateTime.now(), LocalNotifications().budget);
      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}

final localNotificationsProvider = Provider((ref) => LocalNotifications());
final automationErrorProvider = StateProvider<String?>((ref) => null);

class LocalAutomationHost extends ConsumerStatefulWidget {
  const LocalAutomationHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LocalAutomationHost> createState() =>
      _LocalAutomationHostState();
}

class _LocalAutomationHostState extends ConsumerState<LocalAutomationHost>
    with WidgetsBindingObserver {
  bool _running = false;
  bool _again = false;
  Timer? _debounce;
  String? _backgroundError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setup());
  }

  Future<void> _setup() async {
    try {
      if (Platform.isAndroid) {
        await Workmanager().initialize(ledgyBackgroundDispatcher);
        await Workmanager().registerPeriodicTask(
          'ledgy-local-finance',
          'ledgy-local-finance',
          frequency: const Duration(hours: 1),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      }
    } catch (_) {
      _backgroundError = 'Jadwal latar belakang belum aktif. Buka ulang aplikasi untuk mencoba lagi.';
      if (mounted) {
        ref.read(automationErrorProvider.notifier).state = _backgroundError;
      }
    }
    if (mounted) await _run();
  }

  Future<void> _run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final finance = ref.read(localFinanceProvider);
        await finance.generateDue(DateTime.now());
        await finance.checkBudgets(
          DateTime.now(),
          ref.read(localNotificationsProvider).budget,
        );
      } while (_again && mounted);
      if (mounted) {
        ref.read(automationErrorProvider.notifier).state = _backgroundError;
      }
    } catch (_) {
      if (mounted) {
        ref.read(automationErrorProvider.notifier).state = 'Otomatisasi lokal gagal. Data tetap tersimpan; buka ulang aplikasi untuk mencoba lagi.';
      }
    } finally {
      _running = false;
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_run());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A Workmanager isolate uses a separate SQLite connection. Restart the
      // watchers to pick up background writes even if nothing is due now.
      ref.invalidate(transactionsProvider);
      ref.invalidate(recurringRulesProvider);
      ref.invalidate(financeSnapshotProvider);
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(transactionsProvider, (_, next) {
      if (next.hasValue) _schedule();
    });
    ref.listen(budgetsProvider, (_, next) {
      if (next.hasValue) _schedule();
    });
    ref.listen(recurringRulesProvider, (_, next) {
      if (next.hasValue) _schedule();
    });
    return widget.child;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
