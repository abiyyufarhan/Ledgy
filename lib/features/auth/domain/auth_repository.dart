import 'saver_profile.dart';
export 'saver_profile.dart';

class CloudUser {
  const CloudUser(
    this.id,
    this.email, {
    this.name,
    this.avatarUrl,
    this.saverProfile,
  });
  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final SaverProfile? saverProfile;
  String get displayName =>
      name?.trim().isNotEmpty == true ? name!.trim() : email.split('@').first;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  bool get configured;
  CloudUser? get currentUser;
  Stream<CloudUser?> get changes;
  Future<void> signIn(String email, String password);

  /// True when Supabase supplies a session immediately; false when confirmation
  /// is required. Signing up without a session must not initiate a sync.
  Future<bool> signUp(
    String email,
    String password, {
    String? name,
    SaverProfile? saverProfile,
  });
  Future<void> updateSaverProfile(SaverProfile profile);
  Future<void> resendConfirmation(String email);
  Future<void> signOut();
}
