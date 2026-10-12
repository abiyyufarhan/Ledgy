import '../../../../core/database/app_database.dart';

class CategoriesRepository {
  const CategoriesRepository(this._dao);

  final CategoriesDao _dao;

  Stream<List<Category>> watchAll() => _dao.watchActive();
  Stream<int> watchSummary() => _dao.watchActiveCount();
  Future<void> save(CategoriesCompanion value) => _dao.save(value);
  Future<int> softDelete(String id, DateTime now) =>
      _dao.softDelete(id, now.toUtc());
}
