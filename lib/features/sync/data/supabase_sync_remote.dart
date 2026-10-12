import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/sync_models.dart';

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this.client);
  final SupabaseClient client;

  Future<T> _request<T>(String owner, Future<T> Function() action) async {
    if (client.auth.currentUser?.id != owner) throw const SyncSessionChanged();
    try {
      final result = await action();
      if (client.auth.currentUser?.id != owner) {
        throw const SyncSessionChanged();
      }
      return result;
    } on SocketException {
      throw const SyncOffline();
    } on AuthException catch (error) {
      if (error is AuthRetryableFetchException) throw const SyncOffline();
      throw const SyncFailure(
        'Sesi cloud perlu diperbarui. Masuk kembali lalu coba sinkron.',
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST204' || error.code == '42703') {
        throw const SyncFailure(
          'Database cloud perlu migrasi penerima transfer. Data tetap tersimpan di perangkat.',
        );
      }
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const SyncFailure(
          'Database cloud belum siap. Terapkan migrasi sinkronisasi Fase 6.',
        );
      }
      if (error.code == '42501' ||
          error.code == 'PGRST301' ||
          error.code == 'PGRST303') {
        throw const SyncFailure(
          'Akses cloud ditolak. Periksa sesi masuk dan policy database.',
        );
      }
      if (error.code == '23503') {
        throw const SyncFailure(
          'Aset atau kategori belum tersedia di cloud. Coba sinkron lagi.',
        );
      }
      throw const SyncFailure(
        'Server belum menerima perubahan. Antrean disimpan; coba lagi.',
      );
    }
  }

  @override
  Future<SyncWindow> window(String userId) => _request(userId, () async {
    final result = Map<String, dynamic>.from(
      await client.rpc('ledgy_sync_window') as Map,
    );
    return SyncWindow(
      DateTime.parse(result['server_time'] as String).toUtc(),
      hasData: result['has_data'] as bool,
    );
  });

  @override
  Future<Map<String, dynamic>> push(String userId, SyncRecord row) =>
      _request(userId, () async {
        final payload = {...row.data, 'user_id': userId, 'is_dirty': false}
          ..remove('updated_at');
        Future<Map<String, dynamic>> upload() => client
            .from(row.table.sqlName)
            .upsert(payload, onConflict: 'id')
            .select()
            .single();
        try {
          return await upload();
        } on PostgrestException catch (error) {
          // Keep ordinary transactions compatible with servers awaiting the
          // recipient migration. Never discard actual recipient details.
          if (row.table != SyncTable.transactions ||
              !['PGRST204', '42703'].contains(error.code) ||
              payload['recipient_name'] != null ||
              payload['recipient_account'] != null) {
            rethrow;
          }
          payload.remove('recipient_name');
          payload.remove('recipient_account');
          return await upload();
        }
      });

  @override
  Future<List<Map<String, dynamic>>> pull(
    String userId,
    SyncTable table, {
    DateTime? after,
    required DateTime through,
    Map<String, dynamic>? pageAfter,
    required int limit,
  }) => _request(userId, () async {
    var query = client
        .from(table.sqlName)
        .select()
        .eq('user_id', userId)
        .lte('updated_at', through.toUtc().toIso8601String());
    if (after != null) {
      query = query.gt('updated_at', after.toUtc().toIso8601String());
    }
    if (pageAfter != null) {
      // Keyset pagination: offset pagination can skip rows when another device
      // edits an earlier page. The UUID tie-breaker covers equal server times.
      final stamp = DateTime.parse(pageAfter['updated_at'] as String)
          .toUtc()
          .toIso8601String();
      final id = pageAfter['id'] as String;
      query = query.or(
        'updated_at.gt.$stamp,and(updated_at.eq.$stamp,id.gt.$id)',
      );
    }
    return await query
        .order('updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
  });
}
