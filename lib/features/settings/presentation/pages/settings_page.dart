import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/settings_row.dart';
import '../../../auth/domain/auth_repository.dart';
import '../../../sync/domain/sync_models.dart';
import '../../../sync/presentation/sync_providers.dart';
import '../../../security/presentation/security_settings.dart';
import '../../../quick_input/presentation/receipt_settings.dart';
import '../../../quick_input/presentation/parser_settings.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _signingOut = false;
  String? _error;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Data dan perubahan yang belum terkirim tetap disimpan di perangkat. '
          'Anda dapat melanjutkan pencatatan dalam mode lokal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
      await ref.read(syncServiceProvider).refreshLocalStatus();
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cloudUserProvider);
    final status = ref.watch(syncStatusProvider);
    final queue = ref.watch(syncQueueProvider);
    final connection = ref.watch(cloudConnectionProvider);
    final auth = ref.watch(authRepositoryProvider);
    final theme = Theme.of(context);
    final user = session.value ?? auth.currentUser;
    final sync = status.value ?? const SyncStatus();
    final pending = queue.value?.pending ?? sync.pending;
    final busy = sync.phase == SyncPhase.syncing;
    final icon = switch (sync.phase) {
      SyncPhase.synced => Icons.cloud_done_outlined,
      SyncPhase.failed => Icons.cloud_off_outlined,
      SyncPhase.syncing => Icons.sync,
      SyncPhase.waiting => Icons.cloud_upload_outlined,
      SyncPhase.local => Icons.phone_android_outlined,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        leading: IconButton(
          tooltip: 'Kembali ke Dashboard',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.settingsWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Akun & sinkronisasi',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  if (session.isLoading) const LinearProgressIndicator(),
                  SettingsRow(
                    icon: Icons.person_outline,
                    title: user == null
                        ? 'Mode lokal — tanpa akun'
                        : user.email,
                    subtitle: user == null
                        ? 'Catat keuangan tanpa internet. Masuk untuk mencadangkan dan menyinkronkan data antarperangkat.'
                        : 'Kelola informasi akun Anda. Tetap dapat mencatat saat offline.',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.go(user == null ? '/login' : '/profile'),
                  ),
                  if (!auth.configured) ...[
                    const SizedBox(height: AppTheme.fieldSpacing),
                    Text(
                      connection.error ??
                          'Sinkronisasi cloud belum dikonfigurasi.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                  SettingsRow(
                    icon: icon,
                    title: user == null ? 'Mode lokal' : sync.label,
                    titleKey: const ValueKey('sync-status'),
                    subtitle: [
                      sync.message,
                      if (sync.lastSyncedAt != null)
                        'Sinkron terakhir: ${DateFormat('dd MMM yyyy · HH.mm', 'id_ID').format(sync.lastSyncedAt!.toLocal())}',
                    ].join('\n'),
                    trailing: user == null
                        ? null
                        : IconButton(
                            key: const ValueKey('sync-now'),
                            tooltip: busy
                                ? 'Menyinkronkan…'
                                : 'Sinkronkan sekarang',
                            onPressed: busy || _signingOut
                                ? null
                                : () => ref.read(syncServiceProvider).sync(),
                            icon: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sync),
                          ),
                  ),
                  if (queue.isLoading)
                    const LinearProgressIndicator()
                  else if (queue.hasError ||
                      status.hasError ||
                      session.hasError)
                    const Text(
                      'Status belum dapat dimuat. Buka ulang aplikasi untuk mencoba lagi.',
                    )
                  else
                    Text(
                      '$pending perubahan menunggu',
                      key: const ValueKey('sync-pending'),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: AppTheme.fieldSpacing),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTheme.sectionSpacing),
                  if (user == null)
                    FilledButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.login),
                      label: const Text('Masuk / daftar untuk sinkron'),
                    )
                  else
                    SettingsRow(
                      icon: Icons.logout,
                      title: _signingOut
                          ? 'Memproses…'
                          : 'Keluar, lanjut mode lokal',
                      subtitle: 'Data dan perubahan yang belum terkirim tetap tersimpan di perangkat.',
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _signingOut ? null : _signOut,
                    ),
                  const SecuritySettings(),
                  const ReceiptSettings(),
                  const ParserSettings(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
