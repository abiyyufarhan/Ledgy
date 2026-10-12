import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart' show RingProgress;
import '../../../core/widgets/glass_panel.dart';
import '../domain/transaction_draft.dart';
import '../domain/voice_normalizer.dart';
import 'draft_confirmation_sheet.dart';
import 'quick_input_providers.dart';
import 'voice_input_controller.dart';
import 'receipt_scan_page.dart';
import 'receipt_providers.dart';

bool _desktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows ||
  TargetPlatform.linux ||
  TargetPlatform.macOS => true,
  _ => false,
};

Future<void> showQuickInputCommandBar(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppTheme.quickInputWidth,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          child: UncontrolledProviderScope(
            container: container,
            child: const QuickInputBar(autofocus: true, commandBar: true),
          ),
        ),
      ),
    ),
  );
}

/// Ctrl+K focuses the dashboard's existing entry field.
class QuickInputShortcutScope extends StatefulWidget {
  const QuickInputShortcutScope({super.key, required this.child});
  final Widget child;

  @override
  State<QuickInputShortcutScope> createState() =>
      _QuickInputShortcutScopeState();
}

class _QuickInputShortcutScopeState extends State<QuickInputShortcutScope> {
  final _inputFocus = FocusNode();
  @override
  void dispose() {
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_desktop(context)
      ? widget.child
      : _DashboardInputFocus(
          node: _inputFocus,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _inputFocus.requestFocus,
            },
            child: Focus(autofocus: true, child: widget.child),
          ),
        );
}

class _DashboardInputFocus extends InheritedWidget {
  const _DashboardInputFocus({required this.node, required super.child});
  final FocusNode node;
  @override
  bool updateShouldNotify(_DashboardInputFocus oldWidget) =>
      oldWidget.node != node;
}

/// The dashboard shows the entry field immediately on every platform.
class DashboardQuickInput extends StatelessWidget {
  const DashboardQuickInput({super.key});
  @override
  Widget build(BuildContext context) => QuickInputBar(
    compact: true,
    focusNode: context
        .dependOnInheritedWidgetOfExactType<_DashboardInputFocus>()
        ?.node,
  );
}

enum _CardStatus { pending, saved, discarded }

class _DraftCard {
  _DraftCard(this.draft);
  TransactionDraft draft;
  _CardStatus status = _CardStatus.pending;
}

class QuickInputBar extends ConsumerStatefulWidget {
  const QuickInputBar({
    super.key,
    this.autofocus = false,
    this.commandBar = false,
    this.compact = false,
    this.focusNode,
  });
  final bool autofocus;
  final bool commandBar;
  final bool compact;
  final FocusNode? focusNode;

  @override
  ConsumerState<QuickInputBar> createState() => _QuickInputBarState();
}

class _QuickInputBarState extends ConsumerState<QuickInputBar>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  late final FocusNode _focus;
  late final bool _ownsFocus;
  late final VoiceInputController _voice;
  List<_DraftCard> _cards = [];
  bool _working = false;
  bool _parsing = false;
  String? _message;
  bool _error = false;
  bool _recoveryChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_recoveryChecked &&
        !kIsWeb &&
        Theme.of(context).platform == TargetPlatform.android) {
      _recoveryChecked = true;
      unawaited(_recoverReceipt());
    }
  }

  Future<void> _recoverReceipt() async {
    final backend = ref.read(receiptScanBackendProvider);
    setState(() => _working = true);
    try {
      final photo = await ref.read(receiptRecoveryProvider).recoverOnce();
      if (photo == null) return;
      if (!mounted) {
        await backend.remove(photo);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => ReceiptScanPage(initialPhoto: photo),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Foto sebelumnya belum dapat dipulihkan. Pilih foto kembali.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _scanReceipt() async {
    if (_working || _voice.busy || _cards.isNotEmpty) return;
    setState(() => _working = true);
    try {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const ReceiptScanPage()),
      );
      if (mounted && saved == true) {
        setState(() {
          _message = 'Transaksi dari struk disimpan.';
          _error = false;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode();
    WidgetsBinding.instance.addObserver(this);
    _voice = VoiceInputController(
      ref.read(voiceInputBackendProvider),
      onFinal: (text) => unawaited(_submit(text, source: DraftSource.voice)),
    )..addListener(_voiceChanged);
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _voice.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    _text.clear();
    _text.dispose();
    if (_ownsFocus) _focus.dispose();
    _cards.clear();
    super.dispose();
  }

  Future<void> _submit(
    String text, {
    DraftSource source = DraftSource.text,
  }) async {
    if (_working || _voice.busy || _cards.isNotEmpty) return;
    if (text.trim().isEmpty) {
      setState(() {
        _message = 'Ketik transaksi terlebih dahulu.';
        _error = true;
      });
      return;
    }
    setState(() {
      _working = true;
      _parsing = true;
      _message = null;
      _error = false;
    });
    // Keep the async context observed: unobserved stream dependencies pause
    // in Riverpod, so reading only .future can otherwise wait indefinitely.
    final contextSubscription = ref.listenManual(
      parserContextProvider,
      (_, _) {},
    );
    try {
      final ctx = await ref.read(parserContextProvider.future);
      if (!mounted) return;
      final input = source == DraftSource.voice
          ? const VoiceNormalizer().normalize(text)
          : text;
      final parsed = await ref.read(parserPipelineProvider).parse(input, ctx);
      if (!mounted) return;
      // Opt-in diagnostics never retain voice transcripts or OCR text.
      if (source == DraftSource.text) {
        try {
          await ref
              .read(parserFailureRepositoryProvider)
              .record(text, parsed, ctx);
          if (mounted) ref.invalidate(parserFailuresProvider);
        } catch (_) {
          // Diagnostics must not prevent reviewing or saving a transaction.
        }
      }
      if (!mounted) return;
      final drafts = parsed
          .map(
            (draft) => draft.copyWith(
              source: source,
              rawText: source == DraftSource.voice && parsed.length == 1
                  ? text
                  : draft.rawText,
            ),
          )
          .toList();
      setState(() => _parsing = false);
      if (drafts.length > 1) {
        setState(() {
          _cards = drafts.map(_DraftCard.new).toList();
          _text.clear();
        });
      } else {
        final result = await showDraftConfirmationSheet(
          context,
          draft: drafts.single,
        );
        if (!mounted) return;
        setState(() {
          if (result?.action == DraftConfirmationAction.saved) {
            _message = 'Transaksi tersimpan.';
            _text.clear();
          } else if (result?.action == DraftConfirmationAction.discarded) {
            _message = 'Draf dibuang.';
            _text.clear();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Data akun atau kategori belum dapat dimuat. Coba lagi.';
          _error = true;
          // This remains an editable in-memory input, never a persisted transcript.
          if (source == DraftSource.voice) {
            _text.text = text;
          }
          ref.invalidate(parserContextProvider);
        });
      }
    } finally {
      contextSubscription.close();
      if (mounted) {
        setState(() {
          _working = false;
          _parsing = false;
        });
      }
    }
  }

  Future<void> _review(int index) async {
    if (_working || _cards[index].status != _CardStatus.pending) return;
    setState(() => _working = true);
    try {
      final result = await showDraftConfirmationSheet(
        context,
        draft: _cards[index].draft,
      );
      if (!mounted || result == null) return;
      setState(() {
        if (result.action == DraftConfirmationAction.saved) {
          _cards[index].status = _CardStatus.saved;
        } else if (result.action == DraftConfirmationAction.discarded) {
          _cards[index].status = _CardStatus.discarded;
        }
        if (_cards[index].status != _CardStatus.pending) {
          // Finished cards retain a status/amount, not the original utterance.
          _cards[index].draft = result.draft.copyWith(rawText: '', note: null);
        }
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _clear() => setState(() {
    _voice.cancel();
    _cards.clear();
    _text.clear();
    _message = null;
    _error = false;
    _focus.requestFocus();
  });

  @override
  Widget build(BuildContext context) {
    final locked = _working || _cards.isNotEmpty || _voice.busy;
    final warning = _voice.message ?? _message;
    final field = TextField(
      key: const ValueKey('quick-input-text'),
      controller: _text,
      focusNode: _focus,
      autofocus: widget.autofocus,
      enabled: !locked,
      textInputAction: TextInputAction.done,
      onSubmitted: (text) => _submit(text),
      decoration: const InputDecoration(
        labelText: 'Ketik transaksi',
        hintText: 'Makan 35 ribu pakai Tunai',
      ),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_voice.supported)
          IconButton(
            key: const ValueKey('quick-input-microphone'),
            tooltip: _voice.busy ? 'Selesaikan ucapan' : 'Input suara',
            onPressed:
                _working ||
                    _cards.isNotEmpty ||
                    _voice.phase == VoicePhase.preparing ||
                    _voice.phase == VoicePhase.finishing
                ? null
                : () => _voice.busy ? _voice.stop() : _voice.start(),
            icon: Icon(
              _voice.busy
                  ? Icons.stop_circle_outlined
                  : Icons.mic_none_outlined,
            ),
          ),
        if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android)
          IconButton(
            key: const ValueKey('quick-input-camera'),
            tooltip: 'Pindai struk',
            onPressed: locked ? null : _scanReceipt,
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        IconButton(
          key: const ValueKey('quick-input-submit'),
          tooltip: 'Tinjau transaksi',
          onPressed: locked ? null : () => _submit(_text.text),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.compact || widget.commandBar) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Input cepat',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.commandBar)
                  IconButton(
                    tooltip: 'Tutup input cepat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.compactSpacing),
          ],
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth < AppTheme.quickInputStackBreakpoint
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      field,
                      Align(alignment: Alignment.centerRight, child: buttons),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: field),
                      buttons,
                    ],
                  ),
          ),
          if (!widget.compact &&
              (kIsWeb || Theme.of(context).platform != TargetPlatform.android))
            const Text('Pemindaian struk tersedia di Android'),
          if (_parsing)
            const Padding(
              padding: EdgeInsets.only(top: AppTheme.compactSpacing),
              child: LinearProgressIndicator(),
            ),
          if (_voice.busy) ...[
            const SizedBox(height: AppTheme.compactSpacing),
            Row(
              children: [
                const _ListeningRing(),
                const SizedBox(width: AppTheme.fieldSpacing),
                Expanded(
                  child: Text(switch (_voice.phase) {
                    VoicePhase.preparing => 'Menyiapkan mikrofon…',
                    VoicePhase.finishing => 'Menyelesaikan ucapan…',
                    _ =>
                      _voice.onDevice
                          ? 'Mendengarkan di perangkat…'
                          : 'Mendengarkan…',
                  }),
                ),
                IconButton(
                  tooltip: 'Batalkan ucapan',
                  onPressed: _voice.cancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                _voice.interim.isEmpty
                    ? 'Ucapkan transaksi dengan jumlah dan akun.'
                    : _voice.interim,
                key: const ValueKey('quick-input-interim'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          if (warning != null) ...[
            const SizedBox(height: AppTheme.compactSpacing),
            Semantics(
              liveRegion: true,
              child: Text(
                warning,
                style: TextStyle(
                  color: _voice.message != null || _error
                      ? AppTheme.draftWarningColor
                      : AppTheme.mutedText,
                ),
              ),
            ),
            if (_voice.showSettings)
              TextButton(
                onPressed: _voice.openSettings,
                child: const Text('Buka pengaturan'),
              ),
          ],
          if (_cards.isNotEmpty) ...[
            const SizedBox(height: AppTheme.fieldSpacing),
            Text('${_cards.length} draf · tinjau dan simpan satu per satu'),
            for (var i = 0; i < _cards.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.fieldSpacing),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transaksi ${i + 1} · ${_cards[i].draft.amount == null ? 'Jumlah belum diisi' : formatRupiah(_cards[i].draft.amount!)}',
                      ),
                      if (_cards[i].status == _CardStatus.pending)
                        Text(_cards[i].draft.rawText),
                      if (_cards[i].status == _CardStatus.pending)
                        TextButton(
                          key: ValueKey('quick-input-review-$i'),
                          onPressed: _working ? null : () => _review(i),
                          child: const Text('Tinjau & simpan'),
                        )
                      else
                        Text(
                          _cards[i].status == _CardStatus.saved
                              ? 'Tersimpan'
                              : 'Dibuang',
                        ),
                    ],
                  ),
                ),
              ),
            TextButton(
              key: const ValueKey('quick-input-clear'),
              onPressed: _working ? null : _clear,
              child: Text(
                _cards.every((card) => card.status != _CardStatus.pending)
                    ? 'Input transaksi berikutnya'
                    : 'Buang draf yang tersisa',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListeningRing extends StatefulWidget {
  const _ListeningRing();
  @override
  State<_ListeningRing> createState() => _ListeningRingState();
}

class _ListeningRingState extends State<_ListeningRing>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: AppTheme.quickInputPulseDuration,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .45, end: 1).animate(_pulse),
    child: const RingProgress(value: .75, label: '●'),
  );
}
