import '../transaction_draft.dart';
import 'normalizer.dart';
import 'parse_span.dart';
import 'parser_context.dart';

final class AccountMatchResult {
  const AccountMatchResult(
    this.accountId,
    this.toAccountId,
    this.spans,
    this.warnings,
    this.matched,
  );
  final String? accountId, toAccountId;
  final List<ParseSpan> spans;
  final List<DraftWarning> warnings;
  final bool matched;
}

final class _Mention {
  const _Mention(this.account, this.span, this.role, this.fuzzy);
  final ParserAccount account;
  final ParseSpan span;
  final String? role;
  final bool fuzzy;
}

final class AccountMatcher {
  const AccountMatcher();
  List<_Mention> _mentions(String text, ParserContext ctx) {
    final mentions = <_Mention>[];
    const normalizer = Normalizer();
    for (final account in ctx.accounts) {
      for (final alias in [
        account.name,
        ...account.aliases,
      ].map(normalizer.normalize).toSet()) {
        if (alias.isEmpty) continue;
        final parts = alias.split(' ');
        final regex = RegExp(
          '(^|[^a-z0-9])(${RegExp.escape(alias)})(?=\$|[^a-z0-9])',
        );
        final hits = <(int, int, bool)>[
          for (final m in regex.allMatches(text))
            (m.end - alias.length, m.end, false),
        ];
        if (parts.any((p) => p.length >= 5)) {
          final words = RegExp(r'[a-z]+').allMatches(text).toList();
          for (var i = 0; i + parts.length <= words.length; i++) {
            var distance = 0;
            var valid = true;
            for (var j = 0; j < parts.length; j++) {
              if (j > 0 &&
                  text
                      .substring(words[i + j - 1].end, words[i + j].start)
                      .trim()
                      .isNotEmpty) {
                valid = false;
                break;
              }
              final word = words[i + j].group(0)!;
              if (parts[j] == word) continue;
              if (parts[j].length < 5 ||
                  (word.length - parts[j].length).abs() > 1) {
                valid = false;
                break;
              }
              distance += levenshtein(parts[j], word);
            }
            if (valid && distance == 1) {
              hits.add((words[i].start, words[i + parts.length - 1].end, true));
            }
          }
        }
        for (final hit in hits) {
          if (alias == 'tunai' &&
              RegExp(r'\btarik\s*$').hasMatch(text.substring(0, hit.$1))) {
            continue;
          }
          final prefix = RegExp(r'\b(pakai|via|dari|ke|top up)\s*$')
              .firstMatch(text.substring(0, hit.$1));
          mentions.add(
            _Mention(
              account,
              ParseSpan(prefix?.start ?? hit.$1, hit.$2),
              prefix?.group(1),
              hit.$3,
            ),
          );
        }
      }
    }
    mentions.sort((a, b) {
      final exact = (a.fuzzy ? 1 : 0).compareTo(b.fuzzy ? 1 : 0);
      if (exact != 0) return exact;
      return (b.span.end - b.span.start).compareTo(a.span.end - a.span.start);
    });
    final selected = <_Mention>[];
    for (final mention in mentions) {
      if (!selected.any((other) => other.span.overlaps(mention.span))) {
        selected.add(mention);
      }
    }
    return selected..sort((a, b) => a.span.start.compareTo(b.span.start));
  }

  int mentionCount(String text, ParserContext ctx) =>
      _mentions(text, ctx).map((m) => m.account.id).toSet().length;

  AccountMatchResult match(
    String text,
    ParserContext ctx, {
    required bool transfer,
  }) {
    final mentions = _mentions(text, ctx);
    final warnings = <DraftWarning>[];
    final sources = mentions
        .where((m) => m.role != 'ke' && m.role != 'top up')
        .toList();
    final destinations = mentions
        .where((m) => m.role == 'ke' || m.role == 'top up')
        .toList();
    var source = transfer ? sources.firstOrNull : mentions.firstOrNull;
    var destination = transfer ? destinations.firstOrNull : null;
    if (transfer && destination == null && mentions.length > 1) {
      source = mentions.first;
      destination = mentions.skip(1).first;
    }
    if ((transfer ? sources : mentions)
                .map((m) => m.account.id)
                .toSet()
                .length >
            1 &&
        (!transfer || destinations.isNotEmpty)) {
      warnings.add(
        const DraftWarning(
          code: 'MULTIPLE_ACCOUNTS',
          field: DraftField.accountId,
          message: 'Ada beberapa akun asal. Periksa akun yang dipilih.',
        ),
      );
    }
    if (destinations.map((m) => m.account.id).toSet().length > 1) {
      warnings.add(
        const DraftWarning(
          code: 'MULTIPLE_DESTINATIONS',
          field: DraftField.toAccountId,
          message: 'Ada beberapa akun tujuan.',
        ),
      );
    }
    for (final mention in [
      source,
      destination,
    ].nonNulls.where((m) => m.fuzzy)) {
      warnings.add(
        DraftWarning(
          code: 'FUZZY_ACCOUNT',
          field: mention == destination
              ? DraftField.toAccountId
              : DraftField.accountId,
          message:
              'Nama akun mirip dengan ${mention.account.name}. Periksa kembali.',
        ),
      );
    }
    String? defaultId;
    if (source == null) {
      final remaining = removeSpans(text, mentions.map((m) => m.span));
      final explicitUnknown = RegExp(r'\b(?:pakai|via|dari)\s+[a-z]+')
          .hasMatch(remaining);
      if (explicitUnknown) {
        warnings.add(
          const DraftWarning(
            code: 'UNKNOWN_ACCOUNT',
            field: DraftField.accountId,
            message: 'Akun yang disebut belum dikenali. Pilih akun.',
          ),
        );
      } else {
        final validLast = ctx.accounts.any((a) => a.id == ctx.lastAccountId);
        defaultId = validLast ? ctx.lastAccountId : null;
        if (defaultId == null) {
          final memories =
              ctx.memory
                  .where(
                    (m) =>
                        m.keyword.trim().isNotEmpty &&
                        containsPhrase(
                          text,
                          const Normalizer().normalize(m.keyword),
                        ) &&
                        ctx.accounts.any((a) => a.id == m.accountId),
                  )
                  .toList()
                ..sort((a, b) => b.count.compareTo(a.count));
          defaultId = memories.firstOrNull?.accountId;
        }
        warnings.add(
          const DraftWarning(
            code: 'DEFAULT_ACCOUNT',
            field: DraftField.accountId,
            message: 'Akun bawaan dipakai. Periksa akun transaksi.',
          ),
        );
      }
    }
    if (transfer && destination == null) {
      warnings.add(
        const DraftWarning(
          code: 'MISSING_DESTINATION',
          field: DraftField.toAccountId,
          message: 'Akun tujuan belum terbaca.',
        ),
      );
    }
    return AccountMatchResult(
      source?.account.id ?? defaultId,
      destination?.account.id,
      List.unmodifiable(mentions.map((m) => m.span)),
      List.unmodifiable(warnings),
      source != null,
    );
  }
}

int levenshtein(String a, String b) {
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final insertion = current[j - 1] + 1;
      final deletion = previous[j] + 1;
      final replace = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      current[j] = insertion < deletion
          ? (insertion < replace ? insertion : replace)
          : (deletion < replace ? deletion : replace);
    }
    previous = current;
  }
  return previous.last;
}
