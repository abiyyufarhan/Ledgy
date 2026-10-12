import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice_input_backend.dart';

enum VoicePhase { idle, preparing, listening, finishing }

/// Transient UI state only. Generation guards reject late native callbacks.
final class VoiceInputController extends ChangeNotifier {
  VoiceInputController(this.backend, {required this.onFinal});
  final VoiceInputBackend backend;
  final void Function(String) onFinal;
  VoicePhase phase = VoicePhase.idle;
  String interim = '';
  String? message;
  bool showSettings = false;
  bool unavailable = false;
  bool onDevice = false;
  int _generation = 0;
  bool _disposed = false;
  bool _delivered = false;
  Timer? _doneTimer;
  bool get busy => phase != VoicePhase.idle;
  bool get supported => backend.supportedPlatform && !unavailable;
  bool _active(int generation) => !_disposed && generation == _generation;

  Future<void> start() async {
    if (busy || !supported || _disposed) return;
    final generation = ++_generation;
    _doneTimer?.cancel();
    _doneTimer = null;
    _delivered = false;
    message = null;
    showSettings = false;
    interim = '';
    phase = VoicePhase.preparing;
    notifyListeners();
    try {
      final access = await backend.requestMicrophone();
      if (!_active(generation)) return;
      if (access != MicrophoneAccess.granted) {
        _fail(
          generation,
          'Izin mikrofon belum diberikan. ${backend.permissionHelp}',
          settings: access == MicrophoneAccess.blocked,
        );
        return;
      }
      final available = await backend.initialize();
      if (!_active(generation)) return;
      if (!available) {
        unavailable = true;
        _fail(
          generation,
          'Pengenalan suara tidak tersedia pada perangkat ini. Gunakan kolom ketik. ${backend.permissionHelp}',
        );
        return;
      }
      final locales = await backend.locales();
      if (!_active(generation)) return;
      final locale = locales
          .where((id) => id.replaceAll('-', '_').toLowerCase() == 'id_id')
          .firstOrNull;
      if (locale == null) {
        _fail(generation, backend.languageHelp);
        return;
      }
      onDevice = await backend.supportsOnDevice();
      if (!_active(generation)) return;
      phase = VoicePhase.listening;
      notifyListeners();
      await backend.listen(
        localeId: locale,
        onDevice: onDevice,
        onResult: (result) => _result(generation, result),
        onError: (code) {
          final language = code.contains('language') || code.contains('locale');
          final permission = code.contains('permission');
          _fail(
            generation,
            language
                ? backend.languageHelp
                : permission
                ? backend.permissionHelp
                : 'Ucapan belum dapat dikenali. Coba lagi atau gunakan kolom ketik.',
            settings: permission,
          );
        },
        onDone: () => _done(generation),
      );
    } catch (_) {
      _fail(
        generation,
        'Input suara belum dapat dimulai. Coba lagi atau gunakan kolom ketik.',
      );
    }
  }

  void _result(int generation, VoiceResult result) {
    if (!_active(generation) || _delivered) return;
    if (!result.isFinal) {
      interim = result.text;
      notifyListeners();
      return;
    }
    final text = result.text.trim();
    if (text.isEmpty) {
      _fail(generation, 'Belum ada ucapan terbaca. Coba bicara lagi.');
      return;
    }
    _delivered = true;
    _doneTimer?.cancel();
    // Clear the transcript before handing an ephemeral value to the parser.
    interim = '';
    phase = VoicePhase.idle;
    ++_generation;
    unawaited(backend.cancel().catchError((Object _) {}));
    notifyListeners();
    onFinal(text);
  }

  void _done(int generation) {
    if (!_active(generation) || _delivered || _doneTimer != null) return;
    phase = VoicePhase.finishing;
    notifyListeners();
    // Native services can deliver the final result after notListening.
    _doneTimer = Timer(
      const Duration(seconds: 2),
      () => _fail(
        generation,
        'Ucapan belum selesai dikenali. Coba lagi atau gunakan kolom ketik.',
      ),
    );
  }

  void _fail(int generation, String help, {bool settings = false}) {
    if (!_active(generation)) return;
    ++_generation;
    _doneTimer?.cancel();
    _doneTimer = null;
    interim = '';
    phase = VoicePhase.idle;
    message = help;
    showSettings = settings;
    unawaited(backend.cancel().catchError((Object _) {}));
    notifyListeners();
  }

  Future<void> stop() async {
    if (phase != VoicePhase.listening) return;
    final generation = _generation;
    _done(generation);
    try {
      await backend.stop();
    } catch (_) {
      _fail(generation, 'Mikrofon belum dapat dihentikan. Coba lagi.');
    }
  }

  Future<void> openSettings() async {
    try {
      if (!await backend.openSettings() && !_disposed) {
        message = backend.permissionHelp;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) {
        message = backend.permissionHelp;
        notifyListeners();
      }
    }
  }

  void cancel() {
    if (_disposed) return;
    ++_generation;
    _doneTimer?.cancel();
    _doneTimer = null;
    interim = '';
    phase = VoicePhase.idle;
    unawaited(backend.cancel().catchError((Object _) {}));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _doneTimer?.cancel();
    interim = '';
    unawaited(backend.cancel().catchError((Object _) {}));
    super.dispose();
  }
}
