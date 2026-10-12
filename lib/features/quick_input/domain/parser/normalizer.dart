final class Normalizer {
  const Normalizer();
  static const moneyToken = '¤';

  String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\bgo\s+pay\b'), 'gopay')
      .replaceAll(RegExp(r'\bb\s+c\s+a\b'), 'bca')
      .replaceAll(RegExp(r'\btop[\s-]*up\b'), 'top up')
      .replaceAll(RegExp(r'\brp\.?(?=\s|\d|$)|\brupiah\b'), ' $moneyToken ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
