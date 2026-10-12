import '../transaction_draft.dart';
import 'normalizer.dart';
import 'parse_span.dart';
import 'parser_context.dart';

final class CategoryMatchResult {
  const CategoryMatchResult(this.categoryId, this.warnings);
  final String? categoryId;
  final List<DraftWarning> warnings;
}

final class CategoryMatcher {
  const CategoryMatcher();
  static const dictionary = {
    'makanan': [
      'makan',
      'kopi',
      'nasi',
      'warteg',
      'sarapan',
      'roti',
      'teh',
      'bakso',
      'ayam geprek',
      'mie ayam',
    ],
    'transport': [
      'bensin',
      'parkir',
      'ojek',
      'gojek',
      'grab',
      'tol',
      'kereta',
      'ongkir',
      'bus',
    ],
    'tagihan': [
      'listrik',
      'pln',
      'pulsa',
      'internet',
      'wifi',
      'token',
      'kos',
      'paket data',
    ],
    'belanja': ['belanja', 'indomaret', 'alfamart', 'shopee'],
    'hiburan': ['nonton', 'bioskop', 'netflix', 'game', 'spotify'],
    'kesehatan': ['obat', 'dokter', 'apotek', 'vitamin'],
    'gaji': ['gaji', 'gajian', 'bonus'],
    'refund': ['refund'],
    'cashback': ['cashback'],
  };
  static const cafeKeywords = [
    'kopi',
    'ngopi',
    'warkop',
    'cafe',
    'kafe',
    'coffee',
  ];

  static String _name(String text) => const Normalizer()
      .normalize(text)
      .replaceAll('é', 'e')
      .replaceAll(RegExp(r'\s*/\s*'), ' / ');

  CategoryMatchResult match(
    String text,
    ParserContext ctx,
    TransactionType type,
  ) {
    if (type == TransactionType.transfer) {
      return const CategoryMatchResult(null, []);
    }
    final available = ctx.categories.where((c) => c.type == type).toList();
    final memories =
        ctx.memory
            .where(
              (m) =>
                  m.keyword.trim().isNotEmpty &&
                  containsPhrase(
                    text,
                    const Normalizer().normalize(m.keyword),
                  ) &&
                  available.any((c) => c.id == m.categoryId),
            )
            .toList()
          ..sort((a, b) {
            final specific = b.keyword.length.compareTo(a.keyword.length);
            if (specific != 0) return specific;
            final count = b.count.compareTo(a.count);
            return count == 0 ? b.updatedAt.compareTo(a.updatedAt) : count;
          });
    if (memories.isNotEmpty) {
      return CategoryMatchResult(memories.first.categoryId, const []);
    }
    final matches = <(ParserCategory, int, int)>[];
    for (final category in available) {
      final name = _name(category.name);
      final parts = name.split('•').map((part) => part.trim()).toList();
      final leaf = parts.last;
      // A specific subcategory outranks its broad parent. Other children do
      // not inherit all of the parent's keywords (e.g. kopi != Restoran).
      final specific = leaf == 'cafe / warkop'
          ? cafeKeywords
          : parts.length > 1
          ? dictionary[leaf] ?? [leaf]
          : <String>[];
      final specificOffsets = [
        for (final keyword in specific)
          if (containsPhrase(text, keyword)) text.indexOf(keyword),
      ];
      if (specificOffsets.isNotEmpty) {
        specificOffsets.sort();
        matches.add((category, 1, specificOffsets.first));
        continue;
      }
      if (parts.length > 1) continue;
      final family = name.contains('makan')
          ? 'makanan'
          : dictionary.keys.where(name.contains).firstOrNull;
      if (family == null) continue;
      final keywords = dictionary[family]!;
      final offsets = [
        for (final keyword in keywords)
          if (containsPhrase(text, keyword)) text.indexOf(keyword),
      ];
      if (offsets.isNotEmpty) {
        offsets.sort();
        matches.add((category, 0, offsets.first));
      }
    }
    matches.sort((a, b) {
      final specific = b.$2.compareTo(a.$2);
      return specific == 0 ? a.$3.compareTo(b.$3) : specific;
    });
    final strongest = matches.where((m) => m.$2 == matches.firstOrNull?.$2);
    return CategoryMatchResult(matches.firstOrNull?.$1.id, [
      if (strongest.map((m) => m.$1.id).toSet().length > 1)
        const DraftWarning(
          code: 'MULTIPLE_CATEGORIES',
          field: DraftField.categoryId,
          message: 'Ada petunjuk beberapa kategori. Periksa kategori pilihan.',
        ),
    ]);
  }
}
