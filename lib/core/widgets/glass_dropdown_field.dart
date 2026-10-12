import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_menu.dart';

/// Shared form dropdown, preserving nullable "all" filters and disabled items.
class GlassDropdownFormField<T> extends FormField<T> {
  GlassDropdownFormField({
    super.key,
    super.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.icon = Icons.account_balance_wallet_outlined,
    this.itemIconBuilder,
    this.isExpanded = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
  }) : super(builder: (state) => (state as _GlassDropdownState<T>)._build());
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final IconData? icon;
  final IconData Function(T? value)? itemIconBuilder;
  final bool isExpanded;

  @override
  FormFieldState<T> createState() => _GlassDropdownState<T>();
}

class _GlassDropdownState<T> extends FormFieldState<T> {
  @override
  GlassDropdownFormField<T> get widget =>
      super.widget as GlassDropdownFormField<T>;
  bool _opened = false;

  @override
  void didUpdateWidget(covariant GlassDropdownFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  Future<void> _open() async {
    if (_opened) return;
    setState(() => _opened = true);
    final selected = await showGlassMenu<T>(
      context: context,
      anchorContext: context,
      selectedValue: value,
      header: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.compactSpacing,
        ),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: AppTheme.navigationIconSize),
              const SizedBox(width: AppTheme.menuRowPadding),
            ],
            Expanded(
              child: Text(
                widget.decoration.labelText ?? 'Pilih',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      entries: [
        for (final item in widget.items)
          GlassMenuEntry<T>(
            value: item.value,
            label: item.child,
            enabled: item.enabled,
            icon: _iconFor(item.value),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _opened = false);
    if (selected != null) {
      didChange(selected.value);
      widget.onChanged?.call(selected.value);
    }
  }

  Widget? _iconFor(T? item) {
    final icon = widget.itemIconBuilder?.call(item) ?? widget.icon;
    return icon == null ? null : Icon(icon);
  }

  Widget _build() {
    final theme = Theme.of(context);
    final enabled =
        widget.onChanged != null && widget.items.any((item) => item.enabled);
    final matches = widget.items.where((item) => item.value == value);
    final selected = matches.isEmpty ? null : matches.first;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.decoration.labelText,
      child: InkWell(
        onTap: enabled ? _open : null,
        borderRadius: BorderRadius.circular(AppTheme.fieldSpacing),
        child: InputDecorator(
          isFocused: _opened,
          isEmpty: selected == null,
          decoration: widget.decoration
              .copyWith(
                enabled: enabled,
                errorText: errorText,
                prefixIcon: widget.decoration.prefixIcon ?? _iconFor(value),
              )
              .applyDefaults(theme.inputDecorationTheme),
          child: DefaultTextStyle(
            style: theme.textTheme.bodyLarge!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Row(
              children: [
                Expanded(
                  child:
                      selected?.child ??
                      Text(widget.decoration.hintText ?? 'Pilih'),
                ),
                Icon(
                  _opened
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
