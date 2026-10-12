import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/utils/currency_formatter.dart';
import 'local_finance_repository.dart';

class LocalNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_ledgy'),
        windows: WindowsInitializationSettings(
          appName: 'Ledgy 2.0',
          appUserModelId: 'com.ledgy.ledgy2',
          guid: '28cabc1f-7180-4ed3-b4d4-801d8b7bed0a',
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Buka Ledgy'),
      ),
    );
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return true; // Desktop permission is controlled in the operating system.
  }

  Future<bool> budget(BudgetProgress progress, int threshold) async {
    await initialize();
    if (Platform.isAndroid &&
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() !=
            true) {
      return false;
    }
    // Stable positive ID, unlike String.hashCode across runtime sessions.
    var id = threshold;
    for (final unit in progress.budget.id.codeUnits) {
      id = (id * 31 + unit) & 0x7fffffff;
    }
    await _plugin.show(
      id: id,
      title: threshold == 100
          ? 'Anggaran mencapai 100%'
          : 'Anggaran mencapai 80%',
      body:
          '${progress.category}: ${formatRupiah(progress.spent)} dari ${formatRupiah(progress.budget.amount)}.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'ledgy_budgets',
          'Peringatan anggaran',
          channelDescription:
              'Peringatan penggunaan anggaran bulanan 80% dan 100%',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      payload: '/budget-plans',
    );
    return true;
  }
}
