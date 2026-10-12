import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../auth/data/cloud_connection.dart';
import '../../auth/data/supabase_auth_repository.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/sqlite_sync_store.dart';
import '../data/supabase_sync_remote.dart';
import '../domain/sync_models.dart';
import '../domain/sync_service.dart';

final cloudConnectionProvider = Provider<CloudConnection>(
  (ref) => const CloudConnection(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(cloudConnectionProvider)),
);
final cloudUserProvider = StreamProvider<CloudUser?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return Stream<CloudUser?>.multi((controller) {
    final subscription = repository.changes.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.add(repository.currentUser);
    controller.onCancel = subscription.cancel;
  }).distinct(
    (a, b) =>
        a?.id == b?.id &&
        a?.email == b?.email &&
        a?.name == b?.name &&
        a?.avatarUrl == b?.avatarUrl &&
        a?.saverProfile == b?.saverProfile,
  );
});
final syncLocalStoreProvider = Provider<SyncLocalStore>(
  (ref) => SqliteSyncStore(ref.watch(databaseProvider)),
);
final syncRemoteProvider = Provider<SyncRemote>((ref) {
  final client = ref.watch(cloudConnectionProvider).client;
  return client == null
      ? const _UnavailableRemote()
      : SupabaseSyncRemote(client);
});
final syncServiceProvider = Provider<SyncService>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final service = SyncService(
    local: ref.watch(syncLocalStoreProvider),
    remote: ref.watch(syncRemoteProvider),
    userId: () => auth.currentUser?.id,
    project: ref.watch(cloudConnectionProvider).config.url,
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
final syncQueueProvider = StreamProvider<SyncQueue>(
  (ref) => ref.watch(syncLocalStoreProvider).watchQueue(),
);
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final service = ref.watch(syncServiceProvider);
  return Stream<SyncStatus>.multi((controller) {
    final subscription = service.changes.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.add(service.status);
    controller.onCancel = subscription.cancel;
  });
});

class _UnavailableRemote implements SyncRemote {
  const _UnavailableRemote();
  Never _unavailable() =>
      throw const SyncFailure('Sinkronisasi cloud belum dikonfigurasi.');
  @override
  Future<SyncWindow> window(String userId) async => _unavailable();
  @override
  Future<Map<String, dynamic>> push(String userId, SyncRecord row) async =>
      _unavailable();
  @override
  Future<List<Map<String, dynamic>>> pull(
    String userId,
    SyncTable table, {
    DateTime? after,
    required DateTime through,
    Map<String, dynamic>? pageAfter,
    required int limit,
  }) async => _unavailable();
}
