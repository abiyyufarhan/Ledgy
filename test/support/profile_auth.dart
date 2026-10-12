import 'dart:async';

import 'package:ledgy/features/auth/domain/auth_repository.dart';
import 'package:ledgy/features/auth/domain/account_profile_repository.dart';

class ProfileTestAuth implements AuthRepository, AccountProfileRepository {
  @override
  bool get configured => true;
  @override
  CloudUser? currentUser = const CloudUser(
    'profile-owner',
    'abiy@example.com',
    name: 'Abiyyu Farhan',
    saverProfile: SaverProfile.moderate,
  );
  final events = StreamController<CloudUser?>.broadcast();
  @override
  Stream<CloudUser?> get changes => events.stream;
  String? failure;
  String? requestedEmail;
  int deletions = 0;
  void _check() {
    if (failure != null) throw AuthFailure(failure!);
  }

  void _replace({String? name, SaverProfile? profile}) {
    final user = currentUser!;
    currentUser = CloudUser(
      user.id,
      user.email,
      name: name ?? user.name,
      avatarUrl: user.avatarUrl,
      saverProfile: profile ?? user.saverProfile,
    );
    events.add(currentUser);
  }

  @override
  Future<void> updateName(String name) async {
    _check();
    _replace(name: name.trim());
  }

  @override
  Future<void> updateEmail(String email) async {
    _check();
    requestedEmail = email;
  }

  @override
  Future<void> updateSaverProfile(SaverProfile profile) async {
    _check();
    _replace(profile: profile);
  }

  @override
  Future<void> deleteAccount() async {
    deletions++;
    _check();
    currentUser = null;
    events.add(null);
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
    events.add(null);
  }

  @override
  Future<void> resendConfirmation(String email) async {}
  @override
  Future<void> signIn(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<bool> signUp(
    String email,
    String password, {
    String? name,
    SaverProfile? saverProfile,
  }) async => throw UnimplementedError();
}
