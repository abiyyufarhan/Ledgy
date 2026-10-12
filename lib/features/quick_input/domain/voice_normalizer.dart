/// Speech service spellings are normalized before the pure Dart text parser.
final class VoiceNormalizer {
  const VoiceNormalizer();

  String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\bb\s+c\s+a\b'), 'bca')
      .replaceAll(RegExp(r'\bgo\s+pay\b'), 'gopay')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
