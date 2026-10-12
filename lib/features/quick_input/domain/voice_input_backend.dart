enum MicrophoneAccess { granted, denied, blocked }

final class VoiceResult {
  const VoiceResult(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

/// The speech service owns the microphone, never an audio file or recording.
abstract interface class VoiceInputBackend {
  bool get supportedPlatform;
  String get permissionHelp;
  String get languageHelp;
  Future<MicrophoneAccess> requestMicrophone();
  Future<bool> initialize();
  Future<List<String>> locales();
  Future<bool> supportsOnDevice();
  Future<void> listen({
    required String localeId,
    required bool onDevice,
    required void Function(VoiceResult) onResult,
    required void Function(String) onError,
    required void Function() onDone,
  });
  Future<void> stop();
  Future<void> cancel();
  Future<bool> openSettings();
}
