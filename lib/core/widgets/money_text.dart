import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

String formatMoneyInput(int amount) =>
    NumberFormat.decimalPattern('id_ID').format(amount);

/// Integer-only input: no rounding and no conversion through floating point.
final moneyInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (!RegExp(r'^[0-9.\s]*$').hasMatch(newValue.text)) return oldValue;
  final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return const TextEditingValue();
  final amount = int.tryParse(digits);
  if (amount == null) return oldValue;
  final formatted = formatMoneyInput(amount);
  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: formatted.length),
  );
});

class MoneyText extends StatefulWidget {
  const MoneyText({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration = const InputDecoration(labelText: 'Jumlah'),
    this.enabled = true,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final InputDecoration decoration;
  final bool enabled;

  @override
  State<MoneyText> createState() => _MoneyTextState();
}

class _MoneyTextState extends State<MoneyText> {
  late final _controller = TextEditingController(
    text: widget.value == null ? '' : formatMoneyInput(widget.value!),
  );

  @override
  void didUpdateWidget(covariant MoneyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = int.tryParse(_controller.text.replaceAll('.', ''));
    if (widget.value != current) {
      final text = widget.value == null ? '' : formatMoneyInput(widget.value!);
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    enabled: widget.enabled,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    inputFormatters: [moneyInputFormatter],
    style: Theme.of(context).textTheme.bodyLarge,
    decoration: widget.decoration.copyWith(prefixText: 'Rp '),
    onChanged: (text) =>
        widget.onChanged(int.tryParse(text.replaceAll('.', ''))),
  );
}
