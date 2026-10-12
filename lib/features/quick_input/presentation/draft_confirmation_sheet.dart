import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/mvp_screens.dart'
    show showTransactionEditor, showLedgyCategoryPicker, TransactionPickerField;
import '../../../core/database/app_database.dart' show Account, Category;
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/glass_dropdown_field.dart';
import '../../../core/widgets/transaction_form_surface.dart';
import '../../../core/widgets/money_text.dart';
import '../../categories/domain/category_catalog.dart';
import '../domain/draft_validator.dart';
import '../domain/parser/parser_pipeline.dart';
import '../domain/transaction_draft.dart';
import 'quick_input_providers.dart';

enum DraftConfirmationAction { saved, discarded, manual }

final class DraftConfirmationResult {
  const DraftConfirmationResult(this.action, this.draft, {this.originalDraft});
  final DraftConfirmationAction action;
  final TransactionDraft draft;
  final TransactionDraft? originalDraft;
}

/// Entry point for text/voice/receipt parsers. Opening a draft never saves it.
Future<DraftConfirmationResult?> showDraftConfirmationSheet(
  BuildContext context, {
  required TransactionDraft draft,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final sheet = UncontrolledProviderScope(
    container: container,
    child: DraftConfirmationSheet(draft: draft),
  );
  final desktop = switch (Theme.of(context).platform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };
  final result = desktop
      ? await showDialog<DraftConfirmationResult>(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.transactionDialogWidth,
              ),
              child: sheet,
            ),
          ),
        )
      : await showModalBottomSheet<DraftConfirmationResult>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          builder: (sheetContext) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: sheet,
          ),
        );
  if (result?.action == DraftConfirmationAction.manual && context.mounted) {
    TransactionDraft? saved;
    await showTransactionEditor(
      context,
      initialDraft: result!.draft,
      originalDraft: result.originalDraft,
      onDraftSaved: (draft) => saved = draft,
    );
    if (saved != null) {
      return DraftConfirmationResult(DraftConfirmationAction.saved, saved!);
    }
  }
  return result;
}

class DraftConfirmationSheet extends ConsumerStatefulWidget {
  const DraftConfirmationSheet({super.key, required this.draft});
  final TransactionDraft draft;

  @override
  ConsumerState<DraftConfirmationSheet> createState() =>
      _DraftConfirmationSheetState();
}

class _DraftConfirmationSheetState
    extends ConsumerState<DraftConfirmationSheet> {
  static const _validator = DraftValidator();
  late TransactionDraft _draft;
  late final TextEditingController _note;
  late final TextEditingController _recipientName;
  late final TextEditingController _recipientAccount;
  late bool _internalTransfer;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft.copyWith(
      occurredAt: widget.draft.occurredAt ?? DateTime.now().toUtc(),
    );
    _note = TextEditingController(text: _draft.note ?? '');
    _recipientName = TextEditingController(text: _draft.recipientName ?? '');
    _recipientAccount = TextEditingController(
      text: _draft.recipientAccount ?? '',
    );
    _internalTransfer = _draft.toAccountId != null;
  }

  @override
  void dispose() {
    _note.dispose();
    _recipientName.dispose();
    _recipientAccount.dispose();
    super.dispose();
  }

  void _change(TransactionDraft next, List<DraftField> edited) {
    setState(() {
      _draft = next.copyWith(
        warnings: next.warnings
            .where((warning) => !edited.contains(warning.field))
            .toList(),
      );
      _saveError = null;
    });
  }

  // Archived/unknown accounts and wrong-kind categories must be selected again.
  TransactionDraft _resolved(
    List<Account> accounts,
    List<Category> categories,
  ) {
    final categoryId = ref
        .read(quickInputCategoriesProvider)
        .currentId(_draft.categoryId, categories);
    return _draft.copyWith(
      accountId: accounts.any((a) => a.id == _draft.accountId)
          ? _draft.accountId
          : null,
      toAccountId:
          _internalTransfer && accounts.any((a) => a.id == _draft.toAccountId)
          ? _draft.toAccountId
          : null,
      recipientName:
          _draft.type == TransactionType.transfer && !_internalTransfer
          ? _recipientName.text.trim()
          : null,
      recipientAccount:
          _draft.type == TransactionType.transfer && !_internalTransfer
          ? _recipientAccount.text.trim()
          : null,
      categoryId:
          categories.any(
            (c) => c.id == categoryId && c.kind == _draft.type.name,
          )
          ? categoryId
          : null,
    );
  }

  InputDecoration _decoration(
    DraftField field,
    String label,
    List<DraftWarning> issues,
  ) {
    final messages = {
      for (final issue in [...issues, ..._draft.warnings])
        if (issue.field == field) issue.message,
    };
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.fieldSpacing),
      borderSide: const BorderSide(
        color: AppTheme.draftWarningColor,
        width: AppTheme.draftWarningBorderWidth,
      ),
    );
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      helperText: messages.isEmpty ? null : messages.join(' '),
      helperMaxLines: 4,
      helperStyle: const TextStyle(color: AppTheme.draftWarningColor),
      constraints: messages.isEmpty
          ? BoxConstraints.tightFor(
              height:
                  AppTheme.transactionFieldHeight +
                  (MediaQuery.textScalerOf(context).scale(16) - 16) * 2,
            )
          : null,
      enabledBorder: messages.isEmpty ? null : border,
      focusedBorder: messages.isEmpty ? null : border,
      disabledBorder: messages.isEmpty ? null : border,
    );
  }

  Future<void> _pickDate() async {
    final initial = _draft.occurredAt!.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    _change(
      _draft.copyWith(
        occurredAt: DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      ),
      [DraftField.occurredAt],
    );
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final type = _draft.type;
    final selected = await showLedgyCategoryPicker(
      context,
      type: type.name,
      existingCategories: categories,
    );
    if (selected == null || !mounted || _draft.type != type) return;
    final category = ref
        .read(quickInputCategoriesProvider)
        .choice(selected.databaseName, type.name, categories);
    ref.invalidate(quickInputCategoryChoicesProvider);
    _change(_draft.copyWith(categoryId: category.id), [DraftField.categoryId]);
  }

  Future<void> _save() async {
    if (_saving) return;
    final accounts = ref.read(accountsProvider).asData?.value;
    final categories = ref
        .read(quickInputCategoryChoicesProvider)
        .asData
        ?.value;
    if (accounts == null ||
        (categories == null && _draft.type != TransactionType.transfer)) {
      return;
    }
    final candidate = _resolved(accounts, categories ?? []);
    if (_validator.validate(candidate).isNotEmpty) {
      setState(() {});
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await ref
          .read(quickInputActionsProvider)
          .save(original: widget.draft, corrected: candidate);
      if (mounted) {
        Navigator.of(context)
            .pop(DraftConfirmationResult(DraftConfirmationAction.saved, saved));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Transaksi belum tersimpan. Coba simpan kembali.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsState = ref.watch(accountsProvider);
    final categoriesState = ref.watch(quickInputCategoryChoicesProvider);
    final accounts = accountsState.asData?.value ?? <Account>[];
    final categories = categoriesState.asData?.value ?? <Category>[];
    final candidate = _resolved(accounts, categories);
    final issues = _validator.validate(candidate);
    final transfer = _draft.type == TransactionType.transfer;
    final ready =
        accountsState.asData != null &&
        (transfer || categoriesState.asData != null);
    final loading =
        accountsState.isLoading || (!transfer && categoriesState.isLoading);
    final failed =
        accountsState.hasError || (!transfer && categoriesState.hasError);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: TransactionFormSurface(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Transaksi Baru', style: AppTheme.pageTitleStyle(context)),
                if (loading) const LinearProgressIndicator(),
                if (failed) ...[
                  const Text('Pilihan akun atau kategori belum dapat dimuat.'),
                  TextButton(
                    onPressed: () {
                      ref.invalidate(accountsProvider);
                      ref.invalidate(categoriesProvider);
                    },
                    child: const Text('Coba lagi'),
                  ),
                ],
                if (!loading && !failed && accounts.isEmpty)
                  const Text(
                    'Belum ada akun. Tambahkan akun melalui tab Aset.',
                  ),
                const SizedBox(height: AppTheme.pagePadding),
                LayoutBuilder(
                  builder: (context, constraints) =>
                      SegmentedButton<TransactionType>(
                        direction:
                            constraints.maxWidth <
                                AppTheme.draftSegmentMinWidth *
                                    MediaQuery.textScalerOf(context).scale(16) /
                                    16
                            ? Axis.vertical
                            : Axis.horizontal,
                        segments: const [
                          ButtonSegment(
                            value: TransactionType.expense,
                            label: Text('Keluar'),
                          ),
                          ButtonSegment(
                            value: TransactionType.income,
                            label: Text('Masuk'),
                          ),
                          ButtonSegment(
                            value: TransactionType.transfer,
                            label: Text('Transfer'),
                          ),
                        ],
                        selected: {_draft.type},
                        onSelectionChanged: _saving
                            ? null
                            : (value) {
                                _internalTransfer = false;
                                _recipientName.clear();
                                _recipientAccount.clear();
                                _change(
                                  _draft.copyWith(
                                    type: value.first,
                                    categoryId: null,
                                    toAccountId: null,
                                    recipientName: null,
                                    recipientAccount: null,
                                  ),
                                  [
                                    DraftField.type,
                                    DraftField.categoryId,
                                    DraftField.toAccountId,
                                    DraftField.recipientName,
                                    DraftField.recipientAccount,
                                  ],
                                );
                              },
                      ),
                ),
                const SizedBox(height: AppTheme.fieldSpacing),
                MoneyText(
                  key: const ValueKey('draft-amount'),
                  value: _draft.amount,
                  enabled: !_saving,
                  decoration: _decoration(DraftField.amount, 'Jumlah', issues),
                  onChanged: (value) => _change(
                    _draft.copyWith(amount: value),
                    [DraftField.amount],
                  ),
                ),
                const SizedBox(height: AppTheme.transactionFormGap),
                GlassDropdownFormField<String>(
                  initialValue: candidate.accountId,
                  decoration: _decoration(
                    DraftField.accountId,
                    _draft.type == TransactionType.income
                        ? 'Menuju Akun'
                        : 'Dari akun',
                    issues,
                  ),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _change(_draft.copyWith(accountId: value), [
                          DraftField.accountId,
                        ]),
                ),
                const SizedBox(height: AppTheme.transactionFormGap),
                if (transfer && _internalTransfer)
                  GlassDropdownFormField<String>(
                    initialValue: candidate.toAccountId,
                    decoration: _decoration(
                      DraftField.toAccountId,
                      'Ke akun',
                      issues,
                    ),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => _change(
                            _draft.copyWith(toAccountId: value),
                            [DraftField.toAccountId],
                          ),
                  )
                else if (transfer)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('draft-recipient-name'),
                          controller: _recipientName,
                          enabled: !_saving,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            DraftField.recipientName,
                            'Nama Penerima',
                            issues,
                          ),
                          onChanged: (value) => _change(
                            _draft.copyWith(
                              recipientName: value,
                              toAccountId: null,
                            ),
                            [DraftField.recipientName, DraftField.toAccountId],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.fieldSpacing),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('draft-recipient-account'),
                          controller: _recipientAccount,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            DraftField.recipientAccount,
                            'Rekening Penerima',
                            issues,
                          ),
                          onChanged: (value) => _change(
                            _draft.copyWith(
                              recipientAccount: value,
                              toAccountId: null,
                            ),
                            [
                              DraftField.recipientAccount,
                              DraftField.toAccountId,
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  TransactionPickerField(
                    key: const ValueKey('draft-category'),
                    icon: Icons.category_outlined,
                    value: categories
                        .where((c) => c.id == candidate.categoryId)
                        .map(
                          (c) => c.kind == 'income'
                              ? incomeCategoryName(c.name)
                              : c.name,
                        )
                        .firstOrNull,
                    placeholder: 'Pilih kategori dan subkategori',
                    decoration: _decoration(
                      DraftField.categoryId,
                      'Kategori',
                      issues,
                    ),
                    onTap: _saving || !ready
                        ? null
                        : () => _pickCategory(categories),
                  ),
                const SizedBox(height: AppTheme.transactionFormGap),
                TransactionPickerField(
                  onTap: _saving ? null : _pickDate,
                  icon: Icons.calendar_month_outlined,
                  decoration: _decoration(
                    DraftField.occurredAt,
                    'Tanggal',
                    issues,
                  ),
                  value: DateFormat(
                    'd MMM yyyy • HH:mm',
                    'id_ID',
                  ).format(_draft.occurredAt!.toLocal()),
                ),
                const SizedBox(height: AppTheme.transactionFormGap),
                TextField(
                  controller: _note,
                  enabled: !_saving,
                  minLines: 4,
                  maxLines: 6,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  decoration:
                      _decoration(
                        DraftField.note,
                        'Catatan (opsional)',
                        issues,
                      ).copyWith(
                        constraints: const BoxConstraints(),
                        alignLabelWithHint: true,
                        floatingLabelBehavior: FloatingLabelBehavior.auto,
                      ),
                  onChanged: (value) =>
                      _change(_draft.copyWith(note: value), [DraftField.note]),
                ),
                if (_draft.source == DraftSource.receipt) ...[
                  const SizedBox(height: AppTheme.fieldSpacing),
                  Text(
                    'Item struk',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_draft.items.isEmpty)
                    const Text('Belum ada item yang terbaca.'),
                  for (final item in _draft.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.compactSpacing,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: AppTheme.compactSpacing,
                        children: [
                          Text(item.name),
                          Text(formatRupiah(item.amount)),
                        ],
                      ),
                    ),
                ],
                if (_saveError != null) ...[
                  const SizedBox(height: AppTheme.compactSpacing),
                  Text(_saveError!, style: TextStyle(color: scheme.error)),
                ],
                if (ParserPipeline.needsManualCompletion(candidate))
                  const Text(
                    'Lengkapi manual',
                    key: ValueKey('draft-manual-hint'),
                    style: TextStyle(color: AppTheme.draftWarningColor),
                  ),
                const SizedBox(height: AppTheme.fieldSpacing),
                FilledButton(
                  key: const ValueKey('draft-save'),
                  onPressed: _saving || !ready || issues.isNotEmpty
                      ? null
                      : _save,
                  child: Text(_saving ? 'Menyimpan…' : 'Simpan transaksi'),
                ),
                _inputDetails(),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppTheme.compactSpacing,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(
                              DraftConfirmationResult(
                                DraftConfirmationAction.discarded,
                                _draft,
                              ),
                            ),
                      child: const Text('Buang'),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(
                              DraftConfirmationResult(
                                DraftConfirmationAction.manual,
                                candidate,
                                originalDraft: widget.draft,
                              ),
                            ),
                      child: const Text('Edit manual'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputDetails() {
    final label = _draft.confidence >= .8
        ? 'Tinggi'
        : _draft.confidence < .5
        ? 'Rendah'
        : 'Sedang';
    final color = _draft.confidence >= .8
        ? Theme.of(context).colorScheme.primary
        : AppTheme.draftWarningColor;
    return ExpansionTile(
      key: const ValueKey('draft-input-details'),
      title: const Text('Detail input'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppTheme.compactSpacing),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draft.type == TransactionType.transfer)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('draft-transfer-mode'),
              onPressed: _saving
                  ? null
                  : () {
                      _internalTransfer = !_internalTransfer;
                      _change(_draft.copyWith(toAccountId: null), [
                        DraftField.toAccountId,
                        DraftField.recipientName,
                        DraftField.recipientAccount,
                      ]);
                    },
              child: Text(
                _internalTransfer
                    ? 'Transfer ke penerima lain'
                    : 'Transfer antar akun saya',
              ),
            ),
          ),
        Text('Teks asli', style: Theme.of(context).textTheme.labelLarge),
        SelectableText(
          _draft.rawText.isEmpty ? 'Tidak ada teks sumber.' : _draft.rawText,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            label: Text(
              'Keyakinan: $label (${(_draft.confidence * 100).round()}%)',
            ),
            side: BorderSide(color: color),
          ),
        ),
        for (final warning in _draft.warnings)
          Text(
            warning.message,
            style: const TextStyle(color: AppTheme.draftWarningColor),
          ),
        if (_draft.source == DraftSource.receipt)
          TextButton.icon(
            key: const ValueKey('draft-ocr-text'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Teks OCR'),
                content: SingleChildScrollView(
                  child: SelectableText(
                    _draft.rawText.isEmpty
                        ? 'Tidak ada teks sumber.'
                        : _draft.rawText,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.text_snippet_outlined),
            label: const Text('Lihat teks OCR'),
          ),
      ],
    );
  }
}
