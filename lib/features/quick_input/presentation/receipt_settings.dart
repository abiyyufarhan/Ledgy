import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/settings_row.dart';
import 'receipt_providers.dart';
import 'receipt_scan_page.dart';

class ReceiptSettings extends ConsumerStatefulWidget {
  const ReceiptSettings({super.key});
  @override
  ConsumerState<ReceiptSettings> createState() => _ReceiptSettingsState();
}

class _ReceiptSettingsState extends ConsumerState<ReceiptSettings> {
  bool _busy = false;
  String? _error;
  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(receiptStorageProvider).setEnabled(value);
      ref.invalidate(receiptSavePhotoProvider);
      _error = null;
    } catch (_) {
      _error = 'Pengaturan belum dapat disimpan. Coba lagi.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || Theme.of(context).platform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    final preference = ref.watch(receiptSavePhotoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTheme.sectionSpacing),
        Text(
          'Pemindaian struk',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.fieldSpacing),
        SettingsRow(
          icon: Icons.receipt_long_outlined,
          title: 'Simpan foto struk sebagai lampiran',
          subtitle: 'Bawaan mati. Lampiran hanya tersimpan di perangkat ini; foto asli di galeri tetap ada.',
          trailing: Switch(
            key: const ValueKey('receipt-save-photo'),
            value: preference.value ?? false,
            onChanged: preference.hasValue && !_busy ? _toggle : null,
          ),
        ),
        if (_error != null) Text(_error!),
        if (preference.hasError)
          TextButton(
            onPressed: () => ref.invalidate(receiptSavePhotoProvider),
            child: const Text('Muat ulang pengaturan struk'),
          ),
        if (kDebugMode)
          SettingsRow(
            icon: Icons.bug_report_outlined,
            title: 'Debug OCR struk',
            subtitle: 'Ekspor teks dan posisi OCR ke JSON untuk fixture test.',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ReceiptScanPage(debugOnly: true),
              ),
            ),
          ),
      ],
    );
  }
}
