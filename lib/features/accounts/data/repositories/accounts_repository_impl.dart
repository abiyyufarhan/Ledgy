import '../../../../core/database/app_database.dart';

class AccountsRepository {
  const AccountsRepository(this._dao);

  final AccountsDao _dao;

  Stream<List<Account>> watchAll() => _dao.watchActive();
  Stream<int> watchSummary() => _dao.watchActiveCount();
  Future<void> save(AccountsCompanion value) => _dao.save(value);
  Future<int> softDelete(String id, DateTime now) =>
      _dao.softDelete(id, now.toUtc());
}
