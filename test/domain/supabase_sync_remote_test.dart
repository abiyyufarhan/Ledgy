import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/auth/data/cloud_connection.dart';
import 'package:ledgy/features/auth/data/supabase_auth_repository.dart';
import 'package:ledgy/features/auth/domain/saver_profile.dart';
import 'package:ledgy/features/sync/data/supabase_sync_remote.dart';
import 'package:ledgy/features/sync/domain/sync_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/sync_server.dart';

class _Api {
  late final HttpServer server;
  late final SupabaseClient client;
  final requests = <({String method, Uri uri, dynamic body, String? auth})>[];
  bool rejectRpc = false;
  bool offline = false;
  final metadata = <String, dynamic>{};
  final stamp = DateTime.utc(2026, 10, 2, 12, 0, 0, 0, 123);
  String _jwt() {
    String segment(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    return '${segment({'alg': 'HS256', 'typ': 'JWT'})}.${segment({'sub': syncUser, 'role': 'authenticated', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})}.signature';
  }

  Map<String, dynamic> get user => {
    'id': syncUser,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'user@example.com',
    'app_metadata': {},
    'user_metadata': metadata,
    'created_at': '2026-10-02T00:00:00Z',
  };
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        body: body.isEmpty ? null : jsonDecode(body),
        auth: request.headers.value(HttpHeaders.authorizationHeader),
      ));
      final response = request.response;
      response.headers.contentType = ContentType.json;
      dynamic result;
      if (offline) {
        response.statusCode = 503;
        result = {'message': 'offline', 'code': '503'};
      } else if (request.uri.path == '/auth/v1/token') {
        result = {
          'access_token': _jwt(),
          'refresh_token': 'refresh',
          'token_type': 'bearer',
          'expires_in': 86400,
          'user': user,
        };
      } else if (request.uri.path == '/auth/v1/signup') {
        metadata.addAll(
          (requests.last.body['data'] as Map?)?.cast<String, dynamic>() ?? {},
        );
        result = user; // Confirm email: user, but no session.
      } else if (request.uri.path == '/auth/v1/user') {
        if (request.method == 'PUT') {
          metadata.addAll(
            (requests.last.body['data'] as Map).cast<String, dynamic>(),
          );
        }
        result = user;
      } else if (request.uri.path == '/auth/v1/logout') {
        result = {};
      } else if (request.uri.path == '/rest/v1/rpc/ledgy_sync_window') {
        if (rejectRpc) {
          response.statusCode = 404;
          result = {'message': 'Missing function', 'code': 'PGRST202'};
        } else {
          result = {'server_time': stamp.toIso8601String(), 'has_data': true};
        }
      } else if (request.method == 'POST') {
        result = {
          ...(requests.last.body as Map<String, dynamic>),
          'updated_at': stamp.toIso8601String(),
        };
      } else {
        result = [
          {
            'id': walletId,
            'user_id': syncUser,
            'updated_at': stamp.toIso8601String(),
            'deleted_at': stamp.toIso8601String(),
          },
        ];
      }
      response.write(jsonEncode(result));
      await response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'public-test-key',
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  late _Api api;
  setUp(() async {
    api = _Api();
    await api.start();
  });
  tearDown(() => api.close());
  SupabaseAuthRepository auth() => SupabaseAuthRepository(
    CloudConnection(
      config: CloudConfig(
        url: 'http://127.0.0.1:${api.server.port}',
        publicKey: 'sb_publishable_test',
        redirectUrl: 'com.ledgy.ledgy://auth/callback',
      ),
      client: api.client,
    ),
  );

  test('SDK mengirim owner dan memakai timestamp server, pull menyertakan tombstone dan keyset', () async {
    await auth().signIn('user@example.com', 'password123');
    final remote = SupabaseSyncRemote(api.client);
    final window = await remote.window(syncUser);
    expect(window.serverTime, api.stamp);
    expect(window.hasData, isTrue);
    final returned = await remote.push(
      syncUser,
      SyncRecord(SyncTable.accounts, {
        'id': walletId,
        'name': 'Bank Jago',
        'initial_balance': 3000000000,
        'created_at': '2026-10-02T00:00:00Z',
        'updated_at': '2099-01-01T00:00:00Z',
        'deleted_at': null,
        'is_dirty': true,
        'user_id': otherSyncUser,
      }, 1),
    );
    expect(returned['updated_at'], api.stamp.toIso8601String());
    final push = api.requests.last;
    expect(push.uri.queryParameters['on_conflict'], 'id');
    expect(push.body['user_id'], syncUser);
    expect(push.body['is_dirty'], false);
    expect(push.body.containsKey('updated_at'), isFalse);
    expect(push.body['initial_balance'], 3000000000);
    expect(push.auth, startsWith('Bearer '));
    final after = api.stamp.subtract(const Duration(days: 1));
    final rows = await remote.pull(
      syncUser,
      SyncTable.accounts,
      after: after,
      through: api.stamp,
      pageAfter: {'id': walletId, 'updated_at': api.stamp.toIso8601String()},
      limit: 2,
    );
    expect(rows.single['deleted_at'], isNotNull);
    final pull = api.requests.last.uri.queryParametersAll;
    expect(pull['user_id'], ['eq.$syncUser']);
    expect(
      pull['updated_at'],
      containsAll([
        'lte.${api.stamp.toIso8601String()}',
        'gt.${after.toIso8601String()}',
      ]),
    );
    expect(pull['order'], ['updated_at.asc.nullslast,id.asc.nullslast']);
    expect(pull['limit'], ['2']);
    expect(pull['or']!.single, contains('id.gt.$walletId'));
    expect(pull.containsKey('deleted_at'), isFalse);
  });

  test('SDK signup tanpa sesi menunggu konfirmasi; logout offline tetap menghapus sesi lokal', () async {
    final repository = auth();
    expect(await repository.signUp('user@example.com', 'password123'), isFalse);
    expect(repository.currentUser, isNull);
    expect(
      api.requests.last.uri.queryParameters['redirect_to'],
      'com.ledgy.ledgy://auth/callback',
    );
    await repository.signIn('user@example.com', 'password123');
    expect(repository.currentUser?.id, syncUser);
    api.offline = true;
    await repository.signOut();
    expect(repository.currentUser, isNull);
    final count = api.requests.length;
    await expectLater(
      SupabaseSyncRemote(api.client).window(syncUser),
      throwsA(isA<SyncSessionChanged>()),
    );
    expect(api.requests.length, count);
  });

  test(
    'RPC migrasi belum tersedia menghasilkan pesan aman untuk pengguna',
    () async {
      await auth().signIn('user@example.com', 'password123');
      api.rejectRpc = true;
      await expectLater(
        SupabaseSyncRemote(api.client).window(syncUser),
        throwsA(
          isA<SyncFailure>().having(
            (e) => e.message,
            'message',
            contains('Fase 6'),
          ),
        ),
      );
    },
  );

  test('profil penabung tersimpan saat daftar, dibaca saat login, dan pembaruan mempertahankan nama', () async {
    final repository = auth();
    expect(
      await repository.signUp(
        'user@example.com',
        'password123',
        name: 'Abiy',
        saverProfile: SaverProfile.moderate,
      ),
      isFalse,
    );
    expect(api.requests.last.body['data'], {
      'full_name': 'Abiy',
      'saver_profile': 'moderate',
    });
    await repository.signIn('user@example.com', 'password123');
    expect(repository.currentUser?.saverProfile, SaverProfile.moderate);
    await repository.updateSaverProfile(SaverProfile.impulsive);
    expect(repository.currentUser?.saverProfile, SaverProfile.impulsive);
    expect(repository.currentUser?.name, 'Abiy');
    // A fresh SDK client reads the same profile, independently of the first
    // client's session cache. This is the path used by a second device.
    final otherClient = SupabaseClient(
      'http://127.0.0.1:${api.server.port}',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(otherClient.dispose);
    final other = SupabaseAuthRepository(CloudConnection(client: otherClient));
    await other.signIn('user@example.com', 'password123');
    expect(other.currentUser?.saverProfile, SaverProfile.impulsive);
    expect(other.currentUser?.name, 'Abiy');
  });
}
