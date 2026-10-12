class LockConfiguration {
  const LockConfiguration({
    this.biometricEnabled = false,
    this.passwordRecord,
    this.legacyDeviceLock = false,
    this.failedAttempts = 0,
    this.retryAfter,
  });

  final bool biometricEnabled;
  final String? passwordRecord;
  // Existing device locks remain usable after upgrading, including PIN-only
  // Windows Hello, until the user changes that setting.
  final bool legacyDeviceLock;
  final int failedAttempts;
  final DateTime? retryAfter;
  bool get enabled => biometricEnabled || passwordRecord != null;

  LockConfiguration copyWith({
    bool? biometricEnabled,
    String? passwordRecord,
    bool clearPassword = false,
    bool? legacyDeviceLock,
    int? failedAttempts,
    DateTime? retryAfter,
    bool clearRetry = false,
  }) => LockConfiguration(
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    passwordRecord: clearPassword
        ? null
        : passwordRecord ?? this.passwordRecord,
    legacyDeviceLock: legacyDeviceLock ?? this.legacyDeviceLock,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    retryAfter: clearRetry ? null : retryAfter ?? this.retryAfter,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'biometric': biometricEnabled,
    'password': passwordRecord,
    'legacy': legacyDeviceLock,
    'failures': failedAttempts,
    'retryAfter': retryAfter?.toUtc().toIso8601String(),
  };

  factory LockConfiguration.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['biometric'] is! bool ||
        (json['password'] != null && json['password'] is! String) ||
        json['legacy'] is! bool ||
        json['failures'] is! int ||
        (json['failures'] as int) < 0) {
      throw const FormatException('Invalid lock configuration');
    }
    return LockConfiguration(
      biometricEnabled: json['biometric'] as bool,
      passwordRecord: json['password'] as String?,
      legacyDeviceLock: json['legacy'] as bool,
      failedAttempts: json['failures'] as int,
      retryAfter: json['retryAfter'] == null
          ? null
          : DateTime.parse(json['retryAfter'] as String),
    );
  }
}

abstract interface class PasswordHasher {
  Future<String> create(String password);
  Future<bool> verify(String password, String record);
}
