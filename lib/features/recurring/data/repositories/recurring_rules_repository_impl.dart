import '../../../../core/database/app_database.dart';

class RecurringRulesRepository {
  const RecurringRulesRepository(this._dao);

  final RecurringRulesDao _dao;

  Stream<List<RecurringRule>> watchAll() => _dao.watchActive();
  Stream<int> watchSummary() => _dao.watchActiveCount();
  Future<void> save(RecurringRulesCompanion value) => _dao.save(value);
  Future<int> softDelete(String id, DateTime now) =>
      _dao.softDelete(id, now.toUtc());
}
