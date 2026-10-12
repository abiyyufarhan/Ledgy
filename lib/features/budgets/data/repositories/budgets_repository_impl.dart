import '../../../../core/database/app_database.dart';

class BudgetsRepository {
  const BudgetsRepository(this._dao);

  final BudgetsDao _dao;

  Stream<List<Budget>> watchAll() => _dao.watchActive();
  Stream<int> watchSummary() => _dao.watchActiveCount();
  Future<void> save(BudgetsCompanion value) => _dao.save(value);
  Future<int> softDelete(String id, DateTime now) =>
      _dao.softDelete(id, now.toUtc());
}
