import '../transaction_draft.dart';

abstract interface class Clock {
  /// Calendar rules use this value's timezone (device local for SystemClock).
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

final class FixedClock implements Clock {
  const FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

final class ParserAccount {
  ParserAccount({
    required this.id,
    required this.name,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases);
  final String id;
  final String name;
  final List<String> aliases;
}

final class ParserCategory {
  const ParserCategory({
    required this.id,
    required this.name,
    required this.type,
  });
  final String id;
  final String name;
  final TransactionType type;
}

final class KeywordMemory {
  const KeywordMemory({
    required this.keyword,
    this.categoryId,
    this.accountId,
    required this.count,
    required this.updatedAt,
  });
  final String keyword;
  final String? categoryId;
  final String? accountId;
  final int count;
  final DateTime updatedAt;
}

final class ParserContext {
  ParserContext({
    required this.clock,
    required List<ParserAccount> accounts,
    required List<ParserCategory> categories,
    List<KeywordMemory> memory = const [],
    this.lastAccountId,
  }) : accounts = List.unmodifiable(accounts),
       categories = List.unmodifiable(categories),
       memory = List.unmodifiable(memory);
  final Clock clock;
  final List<ParserAccount> accounts;
  final List<ParserCategory> categories;
  final List<KeywordMemory> memory;
  final String? lastAccountId;
}
