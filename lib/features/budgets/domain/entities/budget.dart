class CategoryBudget {
  const CategoryBudget({
    required this.categoryId,
    required this.amount,
    required this.monthStart,
  });

  final String categoryId;
  final int amount;
  final DateTime monthStart;
}
