import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/voice_input_backend.dart';

final class SpeechVoiceBackend implements VoiceInputBackend {
  final SpeechToText _speech = SpeechToText();
  static const _capabilities = MethodChannel('com.ledgy.ledgy2/speech');
  void Function(String)? _onError;
  void Function()? _onDone;
  bool _ready = false;

  // These are the configured native targets in this repository. Linux has no
  // speech_to_text implementation; web/Apple require their own app setup.
  @override
  bool get supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  String get permissionHelp => defaultTargetPlatform == TargetPlatform.windows
      ? 'Buka Pengaturan Windows → Privasi & keamanan → Mikrofon. Aktifkan akses mikrofon untuk aplikasi desktop, lalu coba lagi.'
      : 'Buka Pengaturan → Aplikasi → Ledgy → Izin → Mikrofon, lalu pilih Izinkan saat aplikasi digunakan.';

  @override
  String get languageHelp => defaultTargetPlatform == TargetPlatform.windows
      ? 'Bahasa Indonesia (id_ID) belum tersedia pada layanan ucapan ini. Buka Pengaturan Windows → Waktu & bahasa → Bahasa & wilayah → Opsi bahasa. Unduh paket ucapan Bahasa Indonesia jika tersedia. Jika layanan tidak mendukungnya, gunakan kolom ketik.'
      : 'Bahasa Indonesia (id_ID) belum tersedia. Buka pengaturan layanan pengenalan suara perangkat → Pengenalan ucapan offline → Bahasa, lalu unduh Bahasa Indonesia dan coba lagi. Nama menu dapat berbeda menurut perangkat.';

  @override
  Future<MicrophoneAccess> requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return MicrophoneAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicrophoneAccess.blocked;
    }
    return MicrophoneAccess.denied;
  }

  @override
  Future<bool> initialize() async {
    if (_ready) return true;
    _ready = await _speech.initialize(
      debugLogging: false,
      onError: (error) => _onError?.call(error.errorMsg),
      onStatus: (status) {
        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          _onDone?.call();
        }
      },
      options: [SpeechToText.androidNoBluetooth],
    );
    return _ready;
  }

  @override
  Future<List<String>> locales() async =>
      (await _speech.locales()).map((locale) => locale.localeId).toList();

  @override
  Future<bool> supportsOnDevice() async {
    // Windows speech_to_text uses the local SAPI in-process recognizer.
    if (defaultTargetPlatform == TargetPlatform.windows) return true;
    try {
      return await _capabilities.invokeMethod<bool>('supportsOnDevice') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> listen({
    required String localeId,
    required bool onDevice,
    required void Function(VoiceResult) onResult,
    required void Function(String) onError,
    required void Function() onDone,
  }) async {
    _onError = onError;
    _onDone = onDone;
    await _speech.listen(
      onResult: (result) => onResult(
        VoiceResult(result.recognizedWords, isFinal: result.finalResult),
      ),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        onDevice: onDevice,
        partialResults: true,
        cancelOnError: true,
        autoPunctuation: false,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      ),
    );
    if (_speech.lastError != null) {
      onError(_speech.lastError!.errorMsg);
    }
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() async {
    _onError = null;
    _onDone = null;
    if (_ready) await _speech.cancel();
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
