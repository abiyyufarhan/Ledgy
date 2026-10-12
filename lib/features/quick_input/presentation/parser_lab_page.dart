import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/draft_validator.dart';
import '../domain/parser/parser_inspection.dart';
import 'quick_input_providers.dart';

/// Diagnostic only: no save button, ledger writes, audio or network calls.
class ParserLabPage extends ConsumerStatefulWidget {
  const ParserLabPage({super.key});
  @override
  ConsumerState<ParserLabPage> createState() => _ParserLabPageState();
}

class _ParserLabPageState extends ConsumerState<ParserLabPage> {
  final _text = TextEditingController();
  ParserInspection? _result;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    if (!kDebugMode || _busy) return;
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Tempel atau ketik kalimat terlebih dahulu.');
      return;
    }
    final text = _text.text;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    final subscription = ref.listenManual(parserContextProvider, (_, _) {});
    try {
      final ctx = await ref.read(parserContextProvider.future);
      if (!mounted) return;
      final result = await ref.read(parserPipelineProvider).inspect(text, ctx);
      if (!mounted) return;
      _result = result;
      try {
        await ref
            .read(parserFailureRepositoryProvider)
            .record(text, result.drafts, ctx);
        if (mounted) ref.invalidate(parserFailuresProvider);
      } catch (_) {
        _error =
            'Hasil tersedia, tetapi catatan kegagalan belum dapat disimpan.';
      }
    } catch (_) {
      _error = 'Parser belum dapat dijalankan. Periksa akun dan kategori, lalu coba lagi.';
    } finally {
      subscription.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (!kDebugMode || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await ref.read(parserFailureRepositoryProvider).readAll();
      if (text.isEmpty) {
        _error = 'Belum ada kalimat gagal yang dicatat.';
        return;
      }
      await FilePicker.saveFile(
        dialogTitle: 'Ekspor kalimat gagal',
        fileName: 'parser-failures.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(text)),
        ),
      );
    } catch (_) {
      _error = 'Ekspor belum berhasil. Coba lagi.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(parserFailureRepositoryProvider).clear();
      if (mounted) ref.invalidate(parserFailuresProvider);
    } catch (_) {
      _error = 'Catatan belum dapat dihapus. Coba lagi.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final failures = ref.watch(parserFailuresProvider);
    final ctx = ref.watch(parserContextProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Lab parser')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.settingsWidth),
            child: GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tempel kalimat untuk melihat aturan, hasil, confidence, dan warning. Tidak menyimpan transaksi.',
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  TextField(
                    key: const ValueKey('parser-lab-input'),
                    controller: _text,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Kalimat transaksi',
                      hintText: 'minum kopi 35rb pakai Tunai',
                    ),
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  FilledButton(
                    onPressed: _busy ? null : _parse,
                    child: const Text('Urai kalimat'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_result == null && !_busy)
                    const Text('Hasil akan muncul setelah kalimat diurai.'),
                  if (_result case final result?) ...[
                    const SizedBox(height: AppTheme.sectionSpacing),
                    Text(
                      'Parser ${(result.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms • target < 50 ms',
                    ),
                    for (var i = 0; i < result.drafts.length; i++) ...[
                      const SizedBox(height: AppTheme.fieldSpacing),
                      Text(
                        'Draf ${i + 1}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SelectableText(
                        'Jenis: ${result.drafts[i].type.name}\nJumlah: ${result.drafts[i].amount ?? "kosong"}\nAkun: ${ctx?.accounts.where((a) => a.id == result.drafts[i].accountId).firstOrNull?.name ?? result.drafts[i].accountId ?? "kosong"}\nTujuan: ${result.drafts[i].toAccountId ?? "—"}\nKategori: ${ctx?.categories.where((c) => c.id == result.drafts[i].categoryId).firstOrNull?.name ?? result.drafts[i].categoryId ?? "kosong"}\nTanggal UTC: ${result.drafts[i].occurredAt?.toIso8601String() ?? "kosong"}\nCatatan: ${result.drafts[i].note ?? "—"}\nConfidence: ${(result.drafts[i].confidence * 100).round()}%',
                      ),
                      for (final warning in [
                        ...result.drafts[i].warnings,
                        ...const DraftValidator().validate(
                          result.drafts[i],
                          now: ctx?.clock.now(),
                        ),
                      ])
                        Text(
                          '${warning.code}: ${warning.message}',
                          style: const TextStyle(
                            color: AppTheme.draftWarningColor,
                          ),
                        ),
                    ],
                    const SizedBox(height: AppTheme.sectionSpacing),
                    Text(
                      'Langkah aturan',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (var i = 0; i < result.steps.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${i + 1}. ${result.steps[i].name}'),
                        subtitle: SelectableText(result.steps[i].detail),
                      ),
                  ],
                  const SizedBox(height: AppTheme.sectionSpacing),
                  failures.when(
                    data: (rows) => Text(
                      rows.isEmpty
                          ? 'Belum ada catatan kegagalan lokal.'
                          : '${rows.length} kalimat gagal tersimpan lokal.',
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => TextButton(
                      onPressed: () => ref.invalidate(parserFailuresProvider),
                      child: const Text('Muat ulang catatan kegagalan'),
                    ),
                  ),
                  Wrap(
                    spacing: AppTheme.fieldSpacing,
                    children: [
                      OutlinedButton(
                        onPressed:
                            !_busy && (failures.value?.isNotEmpty ?? false)
                            ? _export
                            : null,
                        child: const Text('Ekspor JSON'),
                      ),
                      TextButton(
                        onPressed:
                            !_busy && (failures.value?.isNotEmpty ?? false)
                            ? _clear
                            : null,
                        child: const Text('Hapus catatan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
