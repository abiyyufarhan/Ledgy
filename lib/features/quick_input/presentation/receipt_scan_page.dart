import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/receipt/ocr_line.dart';
import '../domain/receipt/receipt_scan_backend.dart';
import 'draft_confirmation_sheet.dart';
import 'quick_input_providers.dart';
import 'receipt_providers.dart';

class ReceiptScanPage extends ConsumerStatefulWidget {
  const ReceiptScanPage({super.key, this.initialPhoto, this.debugOnly = false});
  final ReceiptPhoto? initialPhoto;
  final bool debugOnly;
  @override
  ConsumerState<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends ConsumerState<ReceiptScanPage> {
  late final ReceiptScanBackend _backend;
  ReceiptPhoto? _photo;
  List<OcrLine> _lines = [];
  bool _busy = false, _permissionDenied = false;
  bool _confirming = false;
  Duration? _ocrElapsed, _parseElapsed;
  String? _error;
  @override
  void initState() {
    super.initState();
    _backend = ref.read(receiptScanBackendProvider);
    _photo = widget.initialPhoto;
  }

  @override
  void dispose() {
    final photo = _photo;
    if (photo != null && !_busy) unawaited(_backend.remove(photo));
    super.dispose();
  }

  Future<void> _pick(ReceiptImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
      _permissionDenied = false;
    });
    try {
      final photo = await _backend.pick(source);
      if (!mounted) {
        if (photo != null) await _backend.remove(photo);
        return;
      }
      if (photo != null) {
        final previous = _photo;
        _photo = photo;
        _lines = [];
        _ocrElapsed = _parseElapsed = null;
        if (previous != null) await _backend.remove(previous);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _permissionDenied = error.code.contains('denied');
        _error = _permissionDenied
            ? 'Akses kamera atau foto ditolak. Izinkan akses melalui pengaturan aplikasi di sistem.'
            : 'Foto belum dapat dibuka. Coba kamera atau galeri kembali.';
      }
    } on FormatException catch (error) {
      if (mounted) _error = error.message;
    } catch (_) {
      if (mounted) {
        _error =
            'Foto belum dapat disiapkan. Pilih JPG atau PNG yang lebih kecil.';
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else if (_photo != null) {
        await _backend.remove(_photo!);
      }
    }
  }

  Future<void> _scan() async {
    final photo = _photo;
    if (photo == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final subscription = ref.listenManual(parserContextProvider, (_, _) {});
    try {
      final ocrTimer = Stopwatch()..start();
      _lines = await _backend.recognize(photo);
      ocrTimer.stop();
      _ocrElapsed = ocrTimer.elapsed;
      if (!mounted) return;
      if (_lines.isEmpty) {
        _error =
            'Teks belum terbaca. Foto ulang struk dengan cahaya yang cukup.';
        return;
      }
      final parser = ref.read(receiptParserProvider);
      final ctx = await ref.read(parserContextProvider.future);
      if (!mounted) return;
      final parseTimer = Stopwatch()..start();
      final draft = parser
          .parse(_lines, ctx)
          .copyWith(receiptPhotoPath: photo.path);
      parseTimer.stop();
      _parseElapsed = parseTimer.elapsed;
      if (widget.debugOnly && kDebugMode) return;
      setState(() => _confirming = true);
      final result = await showDraftConfirmationSheet(context, draft: draft);
      if (!mounted) return;
      // The repository copies a photo only after explicit Save, if opted in.
      // Every normal confirmation outcome releases the temporary image.
      await _backend.remove(photo);
      _photo = null;
      _lines = [];
      if (!mounted) return;
      if (result?.action == DraftConfirmationAction.saved) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        _error = 'Struk belum dapat diproses. Periksa foto dan coba lagi.';
      }
    } finally {
      subscription.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      } else {
        await _backend.remove(photo);
      }
    }
  }

  Future<void> _export() async {
    if (!kDebugMode || !widget.debugOnly || _lines.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Ekspor fixture OCR',
        fileName: 'receipt-ocr.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ')
                .convert(_lines.map((l) => l.toJson()).toList()),
          ),
        ),
      );
    } catch (_) {
      if (mounted) _error = 'Fixture belum dapat diekspor. Coba lagi.';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else if (_photo != null) {
        await _backend.remove(_photo!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final android =
        !kIsWeb && Theme.of(context).platform == TargetPlatform.android;
    final savePhoto = ref.watch(receiptSavePhotoProvider).value ?? false;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.debugOnly && kDebugMode ? 'Debug OCR struk' : 'Pindai struk',
          ),
        ),
        body: SafeArea(
          child: !android
              ? const Center(
                  child: Text('Pemindaian struk tersedia di Android'),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.pagePadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppTheme.quickInputWidth,
                      ),
                      child: GlassPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Letakkan struk rata dan terang',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppTheme.fieldSpacing),
                            Container(
                              key: const ValueKey('receipt-guide'),
                              height: 300,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.receiptFrameRadius,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _photo == null
                                  ? const Center(
                                      child: Icon(
                                        Icons.receipt_long_outlined,
                                        size: 64,
                                      ),
                                    )
                                  : Image.memory(
                                      _photo!.preview,
                                      key: const ValueKey('receipt-preview'),
                                      fit: BoxFit.contain,
                                    ),
                            ),
                            const SizedBox(height: AppTheme.fieldSpacing),
                            Wrap(
                              spacing: AppTheme.fieldSpacing,
                              runSpacing: AppTheme.compactSpacing,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey('receipt-camera'),
                                  onPressed: _busy
                                      ? null
                                      : () => _pick(ReceiptImageSource.camera),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: const Text('Kamera'),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('receipt-gallery'),
                                  onPressed: _busy
                                      ? null
                                      : () => _pick(ReceiptImageSource.gallery),
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: const Text('Galeri'),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppTheme.fieldSpacing),
                            Text(
                              savePhoto
                                  ? 'Foto akan disimpan sebagai lampiran lokal hanya setelah transaksi disimpan.'
                                  : 'Foto diproses di perangkat dan dihapus setelah selesai. Tidak dikirim ke server.',
                            ),
                            if (_error != null)
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            if (_permissionDenied)
                              TextButton(
                                onPressed: () => openAppSettings(),
                                child: const Text('Buka pengaturan sistem'),
                              ),
                            if (_busy && !_confirming)
                              const LinearProgressIndicator(),
                            if (kDebugMode &&
                                _ocrElapsed != null &&
                                _parseElapsed != null)
                              Text(
                                'OCR ${_ocrElapsed!.inMilliseconds} ms + parser ${_parseElapsed!.inMilliseconds} ms = ${(_ocrElapsed! + _parseElapsed!).inMilliseconds} ms • target < 3000 ms (tanpa pemilih foto dan konfirmasi)',
                              ),
                            const SizedBox(height: AppTheme.fieldSpacing),
                            FilledButton.icon(
                              key: const ValueKey('receipt-scan'),
                              onPressed: _busy || _photo == null ? null : _scan,
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('Baca struk'),
                            ),
                            if (kDebugMode &&
                                widget.debugOnly &&
                                _lines.isNotEmpty) ...[
                              Text('${_lines.length} potongan OCR'),
                              SelectableText(
                                mergeOcrLines(_lines)
                                    .map((l) => l.text)
                                    .join('\n'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _export,
                                icon: const Icon(Icons.download),
                                label: const Text('Ekspor OcrLine ke JSON'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
