import '../../../../core/database/app_database.dart';

class TransactionsRepository {
  const TransactionsRepository(this._dao);

  final TransactionsDao _dao;

  Stream<List<Transaction>> watchAll() => _dao.watchActive();
  Stream<List<Transaction>> watchForPeriod(DateTime start, DateTime end) =>
      _dao.watchForPeriod(start.toUtc(), end.toUtc());
  Stream<int> watchSummary() => _dao.watchActiveCount();
  Future<void> save(TransactionsCompanion value) => _dao.save(value);
  Future<int> softDelete(String id, DateTime now) =>
      _dao.softDelete(id, now.toUtc());
  Future<int> restore(String id, DateTime now) => _dao.restore(id, now.toUtc());
}
