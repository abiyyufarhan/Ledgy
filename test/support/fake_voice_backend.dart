import 'dart:async';

import 'package:ledgy/features/quick_input/domain/voice_input_backend.dart';

class FakeVoiceBackend implements VoiceInputBackend {
  @override
  bool supportedPlatform = true;
  MicrophoneAccess access = MicrophoneAccess.granted;
  Completer<MicrophoneAccess>? permissionGate;
  bool available = true;
  bool local = true;
  List<String> languages = ['en_US', 'id_ID'];
  int permissionRequests = 0,
      initializations = 0,
      cancels = 0,
      stops = 0,
      settings = 0;
  String? listenedLocale;
  bool? listenedOnDevice;
  void Function(VoiceResult)? result;
  void Function(String)? error;
  void Function()? done;
  @override
  String get permissionHelp => 'Aktifkan Mikrofon di Pengaturan sistem.';
  @override
  String get languageHelp =>
      'Unduh paket Bahasa Indonesia melalui pengaturan pengenalan ucapan offline.';
  @override
  Future<MicrophoneAccess> requestMicrophone() async {
    permissionRequests++;
    return permissionGate == null ? access : permissionGate!.future;
  }

  @override
  Future<bool> initialize() async {
    initializations++;
    return available;
  }

  @override
  Future<List<String>> locales() async => languages;
  @override
  Future<bool> supportsOnDevice() async => local;
  @override
  Future<void> listen({
    required String localeId,
    required bool onDevice,
    required void Function(VoiceResult) onResult,
    required void Function(String) onError,
    required void Function() onDone,
  }) async {
    listenedLocale = localeId;
    listenedOnDevice = onDevice;
    result = onResult;
    error = onError;
    done = onDone;
  }

  @override
  Future<void> stop() async {
    stops++;
    done?.call();
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<bool> openSettings() async {
    settings++;
    return true;
  }

  void emit(String text, {bool finalResult = false}) =>
      result?.call(VoiceResult(text, isFinal: finalResult));
}
