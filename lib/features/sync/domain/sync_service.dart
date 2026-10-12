import 'dart:async';

import 'sync_models.dart';

/// A single flight pushes parents before children, acknowledges server versions,
/// then pulls a bounded server-time window, including soft-delete tombstones.
/// For competing dirty edits, the last write accepted by Supabase wins. Device
/// timestamps are never compared to choose the winner.
class SyncService {
  SyncService({
    required this.local,
    required this.remote,
    required this.userId,
    required this.project,
    this.pageSize = 200,
    this.requestTimeout = const Duration(seconds: 30),
  });

  final SyncLocalStore local;
  final SyncRemote remote;
  final String? Function() userId;
  final String project;
  final int pageSize;
  final Duration requestTimeout;
  final _changes = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();
  Future<void>? _flight;
  bool _disposed = false;
  bool _maintenance = false;
  SyncStatus get status => _status;
  Stream<SyncStatus> get changes => _changes.stream;

  void _emit(SyncPhase phase, String message, {int? pending, DateTime? last}) {
    if (_disposed) return;
    _status = SyncStatus(
      phase: phase,
      pending: pending ?? _status.pending,
      lastSyncedAt: last ?? _status.lastSyncedAt,
      message: message,
    );
    _changes.add(_status);
  }

  Future<void> refreshLocalStatus() async {
    if (_disposed) return;
    try {
      await _refreshLocalStatus();
    } catch (_) {
      _emit(SyncPhase.failed, 'Status lokal belum dapat dibaca. Coba lagi.');
    }
  }

  Future<void> _refreshLocalStatus() async {
    final queue = await local.queue();
    final last = await local.lastSuccess();
    if (_disposed || _flight != null) return;
    if (userId() == null) {
      _emit(
        SyncPhase.local,
        'Data tetap tersimpan di perangkat. Masuk untuk sinkronisasi.',
        pending: queue.pending,
        last: last,
      );
    } else if (queue.pending > 0) {
      _emit(
        SyncPhase.waiting,
        '${queue.pending} perubahan menunggu dikirim.',
        pending: queue.pending,
        last: last,
      );
    } else if (_status.phase == SyncPhase.local) {
      _emit(
        SyncPhase.waiting,
        'Memeriksa perubahan dari perangkat lain.',
        pending: 0,
        last: last,
      );
    }
  }

  Future<void> sync() {
    if (_disposed || _maintenance) return Future.value();
    if (_flight != null) return _flight!;
    final completer = Completer<void>();
    _flight = completer.future;
    unawaited(
      _run().then(
        (_) {
          _flight = null;
          completer.complete();
        },
        onError: (Object error, StackTrace stack) {
          _flight = null;
          completer.completeError(error, stack);
        },
      ),
    );
    return completer.future;
  }

  /// Finish any in-flight upload before account maintenance starts. New sync
  /// attempts wait for the normal scheduler rather than racing ledger changes.
  Future<T> withMaintenance<T>(Future<T> Function() action) async {
    if (_maintenance) {
      throw StateError('Account maintenance is already running.');
    }
    _maintenance = true;
    try {
      await _flight;
      return await action();
    } finally {
      _maintenance = false;
      await refreshLocalStatus();
    }
  }

  void _checkSession(String expected) {
    if (_disposed || userId() != expected) throw const SyncSessionChanged();
  }

  Future<T> _request<T>(String owner, Future<T> Function() action) async {
    _checkSession(owner);
    final value = await action().timeout(requestTimeout);
    _checkSession(owner);
    return value;
  }

  Future<void> _run() async {
    final owner = userId();
    try {
      if (owner == null) {
        final q = await local.queue();
        _emit(
          SyncPhase.local,
          'Masuk untuk sinkronisasi. Antrean tetap tersimpan lokal.',
          pending: q.pending,
        );
        return;
      }
      final q = await local.queue();
      _emit(
        SyncPhase.syncing,
        'Mengirim dan mengambil perubahan…',
        pending: q.pending,
        last: await local.lastSuccess(),
      );
      final initial = await _request(owner, () => remote.window(owner));
      await local.prepare(owner, project, hasRemoteData: initial.hasData);
      _checkSession(owner);
      for (final table in SyncTable.values) {
        final rows = await local.dirty(table);
        for (final row in rows) {
          final returned = await _request(owner, () => remote.push(owner, row));
          _validateOwner(returned, owner, row.id);
          await local.acknowledge(row, returned);
          _checkSession(owner);
        }
      }
      // Obtain the upper bound AFTER push. Push acknowledgements are not used as
      // the pull cursor: an older, unseen remote change must not be skipped.
      final window = await _request(owner, () => remote.window(owner));
      final since = await local.cursor();
      for (final table in SyncTable.values) {
        Map<String, dynamic>? pageAfter;
        do {
          final page = await _request(
            owner,
            () => remote.pull(
              owner,
              table,
              after: since,
              through: window.serverTime,
              pageAfter: pageAfter,
              limit: pageSize,
            ),
          );
          for (final row in page) {
            _validateOwner(row, owner, row['id'] as String);
          }
          await local.merge(table, page);
          _checkSession(owner);
          if (page.length < pageSize) break;
          final last = page.last;
          if (pageAfter != null &&
              last['id'] == pageAfter['id'] &&
              last['updated_at'] == pageAfter['updated_at']) {
            throw const SyncFailure(
              'Server mengembalikan halaman berulang. Coba sinkron lagi.',
            );
          }
          pageAfter = last;
        } while (true);
      }
      await local.complete(window.serverTime);
      final pending = (await local.queue()).pending;
      _emit(
        pending == 0 ? SyncPhase.synced : SyncPhase.waiting,
        pending == 0
            ? 'Semua perubahan telah tersinkron.'
            : 'Perubahan baru menunggu dikirim.',
        pending: pending,
        last: window.serverTime,
      );
    } on SyncSessionChanged {
      _emit(
        SyncPhase.local,
        'Sesi berubah. Antrean tetap tersimpan di perangkat.',
      );
    } on SyncOffline {
      _emit(
        SyncPhase.waiting,
        'Menunggu koneksi internet. Antrean akan dicoba ulang.',
      );
    } on TimeoutException {
      _emit(
        SyncPhase.waiting,
        'Koneksi terlalu lama. Antrean akan dicoba ulang.',
      );
    } on SyncFailure catch (error) {
      _emit(SyncPhase.failed, error.message);
    } catch (_) {
      _emit(
        SyncPhase.failed,
        'Sinkronisasi gagal. Data lokal tetap aman; coba lagi.',
      );
    } finally {
      if (!_disposed) {
        try {
          final pending = (await local.queue()).pending;
          _emit(_status.phase, _status.message, pending: pending);
        } catch (_) {
          _emit(
            SyncPhase.failed,
            'Antrean lokal belum dapat dibaca. Coba lagi.',
          );
        }
      }
    }
  }

  void _validateOwner(Map<String, dynamic> row, String owner, String id) {
    if (row['user_id'] != owner ||
        row['id'] != id ||
        row['updated_at'] == null) {
      throw const SyncFailure(
        'Respons sinkronisasi tidak sesuai akun yang masuk.',
      );
    }
    DateTime.parse(row['updated_at'] as String);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _changes.close();
  }
}
