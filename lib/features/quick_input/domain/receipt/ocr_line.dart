import 'dart:math' as math;

final class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  final String text;
  final double left, top, right, bottom;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
  factory OcrLine.fromJson(Map<String, dynamic> json) => OcrLine(
    text: json['text'] as String,
    left: (json['left'] as num).toDouble(),
    top: (json['top'] as num).toDouble(),
    right: (json['right'] as num).toDouble(),
    bottom: (json['bottom'] as num).toDouble(),
  );
  Map<String, Object> toJson() => {
    'text': text,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

/// Cluster by center-y, allowing slight skew, without merging adjacent rows.
List<OcrLine> mergeOcrLines(List<OcrLine> input) {
  final sorted =
      input
          .where(
            (l) =>
                l.text.trim().isNotEmpty &&
                [l.left, l.top, l.right, l.bottom].every((v) => v.isFinite) &&
                l.height > 0 &&
                l.right >= l.left,
          )
          .toList()
        ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final groups = <List<OcrLine>>[];
  for (final line in sorted) {
    List<OcrLine>? nearest;
    var distance = double.infinity;
    for (final group in groups) {
      final center =
          group.fold<double>(0, (sum, l) => sum + l.centerY) / group.length;
      final height =
          group.fold<double>(0, (sum, l) => sum + l.height) / group.length;
      final delta = (line.centerY - center).abs();
      if (delta <= math.max(3, math.min(height, line.height) * .55) &&
          delta < distance) {
        // Overlapping x means this is probably another line, not a fragment.
        if (group.any(
          (l) =>
              math.min(l.right, line.right) - math.max(l.left, line.left) >
              math.min(l.right - l.left, line.right - line.left) * .2,
        )) {
          continue;
        }
        nearest = group;
        distance = delta;
      }
    }
    if (nearest == null) {
      groups.add([line]);
    } else {
      nearest.add(line);
    }
  }
  return [
    for (final group in groups)
      (() {
        group.sort((a, b) => a.left.compareTo(b.left));
        return OcrLine(
          text: group.map((l) => l.text.trim()).join(' '),
          left: group.map((l) => l.left).reduce(math.min),
          top: group.map((l) => l.top).reduce(math.min),
          right: group.map((l) => l.right).reduce(math.max),
          bottom: group.map((l) => l.bottom).reduce(math.max),
        );
      })(),
  ]..sort((a, b) => a.centerY.compareTo(b.centerY));
}
