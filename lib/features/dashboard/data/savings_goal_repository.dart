import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../local/data/local_finance_repository.dart';
import '../../local/presentation/local_providers.dart';

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
  });
  final String id;
  final String name;
  final int target;
  final int saved;
  double get progress => saved / target;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'target': target,
    'saved': saved,
  };
}

class SavingsGoalRepository {
  SavingsGoalRepository(this.finance);
  final LocalFinanceRepository finance;
  static const storageKey = 'dashboard:savings-goals:v1';

  Future<List<SavingsGoal>> read() async {
    final value = await finance.state(storageKey);
    if (value == null) return [];
    return (jsonDecode(value) as List).map((item) {
      final data = item as Map<String, dynamic>;
      final goal = SavingsGoal(
        id: data['id'] as String,
        name: data['name'] as String,
        target: data['target'] as int,
        saved: data['saved'] as int,
      );
      _validate(goal);
      return goal;
    }).toList();
  }

  Future<void> write(List<SavingsGoal> goals) async {
    for (final goal in goals) {
      _validate(goal);
    }
    await finance.setState(
      storageKey,
      jsonEncode(goals.map((goal) => goal.toJson()).toList()),
    );
  }

  void _validate(SavingsGoal goal) {
    if (goal.id.isEmpty ||
        goal.name.trim().isEmpty ||
        goal.target <= 0 ||
        goal.saved < 0) {
      throw ArgumentError('Target tabungan tidak valid.');
    }
  }
}

final savingsGoalRepositoryProvider = Provider(
  (ref) => SavingsGoalRepository(ref.watch(localFinanceProvider)),
);
final savingsGoalsProvider =
    AsyncNotifierProvider<SavingsGoals, List<SavingsGoal>>(SavingsGoals.new);

class SavingsGoals extends AsyncNotifier<List<SavingsGoal>> {
  @override
  Future<List<SavingsGoal>> build() =>
      ref.watch(savingsGoalRepositoryProvider).read();

  Future<void> save({
    String? id,
    required String name,
    required int target,
    required int saved,
  }) async {
    final current = await future;
    final goal = SavingsGoal(
      id: id ?? const Uuid().v4(),
      name: name.trim(),
      target: target,
      saved: saved,
    );
    final next = [
      for (final item in current)
        if (item.id != goal.id) item,
      goal,
    ];
    await ref.read(savingsGoalRepositoryProvider).write(next);
    state = AsyncData(next);
  }

  Future<void> remove(String id) async {
    final next = (await future).where((g) => g.id != id).toList();
    await ref.read(savingsGoalRepositoryProvider).write(next);
    state = AsyncData(next);
  }
}
