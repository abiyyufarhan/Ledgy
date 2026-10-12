import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/settings_row.dart';
import 'quick_input_providers.dart';
import 'parser_lab_page.dart';

class ParserSettings extends ConsumerStatefulWidget {
  const ParserSettings({super.key});
  @override
  ConsumerState<ParserSettings> createState() => _ParserSettingsState();
}

class _ParserSettingsState extends ConsumerState<ParserSettings> {
  bool _busy = false;
  String? _error;
  Future<void> _manage({bool clear = false}) async {
    if (_busy) return;
    final repository = ref.read(parserFailureRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (clear) {
        await repository.clear();
        if (mounted) ref.invalidate(parserFailuresProvider);
      } else {
        final rows = await repository.readAll();
        if (rows.isEmpty) {
          _error = 'Belum ada kalimat gagal yang dicatat.';
          return;
        }
        await FilePicker.saveFile(
          dialogTitle: 'Ekspor kalimat gagal',
          fileName: 'parser-failures.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(rows)),
          ),
        );
      }
    } catch (_) {
      _error = 'Catatan belum dapat diproses. Coba lagi.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(parserFailureRepositoryProvider).setEnabled(enabled);
      if (mounted) ref.invalidate(parserFailureRecordingProvider);
    } catch (_) {
      _error = 'Pengaturan belum dapat disimpan. Coba lagi.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(parserFailureRecordingProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTheme.sectionSpacing),
        Text('Input cepat', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTheme.fieldSpacing),
        SettingsRow(
          icon: Icons.manage_search_outlined,
          title: 'Catat kalimat gagal diurai',
          subtitle: 'Bawaan mati. Hanya teks ketikan disimpan lokal, maksimal 500 kalimat. Suara dan OCR tidak dicatat.',
          trailing: Switch(
            key: const ValueKey('parser-record-failures'),
            value: enabled.value ?? false,
            onChanged: enabled.hasValue && !_busy ? _toggle : null,
          ),
        ),
        if (_error != null) Text(_error!),
        Wrap(
          spacing: AppTheme.fieldSpacing,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _manage(),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Ekspor kegagalan JSON'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _manage(clear: true),
              child: const Text('Hapus catatan kegagalan'),
            ),
          ],
        ),
        if (enabled.hasError)
          TextButton(
            onPressed: () => ref.invalidate(parserFailureRecordingProvider),
            child: const Text('Muat ulang pengaturan parser'),
          ),
        if (kDebugMode)
          SettingsRow(
            icon: Icons.science_outlined,
            title: 'Lab parser',
            subtitle: 'Periksa aturan, confidence, warning, dan ekspor catatan lokal.',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ParserLabPage()),
            ),
          ),
      ],
    );
  }
}
