final class ParseSpan {
  const ParseSpan(this.start, this.end);
  final int start;
  final int end;
  bool overlaps(ParseSpan other) => start < other.end && end > other.start;
}

String removeSpans(String text, Iterable<ParseSpan> spans) {
  final characters = text.split('');
  for (final span in spans) {
    for (var i = span.start; i < span.end && i < characters.length; i++) {
      characters[i] = ' ';
    }
  }
  return characters.join('').replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool containsPhrase(String text, String phrase) =>
    RegExp('(^|[^a-z0-9])${RegExp.escape(phrase)}(?=\$|[^a-z0-9])')
        .hasMatch(text);
