/// Account management capabilities, separate from sign-in and sign-up.
abstract interface class AccountProfileRepository {
  Future<void> updateName(String name);
  Future<void> updateEmail(String email);
  Future<void> deleteAccount();
}
