import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgy/features/quick_input/domain/voice_input_backend.dart';
import 'package:ledgy/features/quick_input/presentation/voice_input_controller.dart';

import 'support/fake_voice_backend.dart';

void main() {
  late FakeVoiceBackend backend;
  late VoiceInputController controller;
  late List<String> finals;
  setUp(() {
    backend = FakeVoiceBackend();
    finals = [];
    controller = VoiceInputController(backend, onFinal: finals.add);
  });
  tearDown(() => controller.dispose());

  test('id_ID on-device, interim langsung dan final hanya satu kali', () async {
    await controller.start();
    expect(backend.listenedLocale, 'id_ID');
    expect(backend.listenedOnDevice, isTrue);
    expect(controller.phase, VoicePhase.listening);
    backend.emit('makan tiga puluh');
    expect(controller.interim, 'makan tiga puluh');
    expect(finals, isEmpty);
    backend.emit('makan tiga puluh ribu', finalResult: true);
    backend.emit('makan tiga puluh ribu', finalResult: true);
    expect(finals, ['makan tiga puluh ribu']);
    expect(controller.interim, isEmpty);
    expect(controller.phase, VoicePhase.idle);
    expect(backend.cancels, greaterThan(0));
  });
  test('id-ID diterima dan layanan biasa dipakai tanpa on-device', () async {
    backend.languages = ['id-ID'];
    backend.local = false;
    await controller.start();
    expect(backend.listenedLocale, 'id-ID');
    expect(backend.listenedOnDevice, isFalse);
  });
  for (final access in [MicrophoneAccess.denied, MicrophoneAccess.blocked]) {
    test(
      'izin $access berhenti sebelum speech dan menjelaskan Pengaturan',
      () async {
        backend.access = access;
        await controller.start();
        expect(backend.initializations, 0);
        expect(controller.message, contains('Pengaturan'));
        expect(controller.showSettings, access == MicrophoneAccess.blocked);
        expect(controller.busy, isFalse);
        if (controller.showSettings) {
          await controller.openSettings();
          expect(backend.settings, 1);
        }
      },
    );
  }
  test(
    'locale hilang menyediakan instruksi unduh, tidak mendengarkan bahasa lain',
    () async {
      backend.languages = ['en_US', 'id_MY'];
      await controller.start();
      expect(controller.message, contains('Unduh paket Bahasa Indonesia'));
      expect(backend.listenedLocale, isNull);
    },
  );
  test('platform tanpa speech tidak meminta izin', () async {
    backend.supportedPlatform = false;
    await controller.start();
    expect(controller.supported, isFalse);
    expect(backend.permissionRequests, 0);
  });
  test('initialize unavailable menyembunyikan mikrofon', () async {
    backend.available = false;
    await controller.start();
    expect(controller.supported, isFalse);
    expect(controller.message, contains('tidak tersedia'));
  });
  test('cancel sebelum izin selesai tidak menyalakan mikrofon', () async {
    backend.permissionGate = Completer<MicrophoneAccess>();
    final start = controller.start();
    controller.cancel();
    backend.permissionGate!.complete(MicrophoneAccess.granted);
    await start;
    expect(backend.initializations, 0);
    expect(controller.phase, VoicePhase.idle);
  });
  test('hasil native terlambat setelah cancel tidak membuka draf', () async {
    await controller.start();
    backend.emit('transkrip sementara');
    controller.cancel();
    backend.emit('transkrip final', finalResult: true);
    expect(finals, isEmpty);
    expect(controller.interim, isEmpty);
  });
  test(
    'error bahasa/izin hanya bantuan dan tidak membocorkan error native',
    () async {
      await controller.start();
      backend.error!('error_language_not_supported');
      expect(controller.message, backend.languageHelp);
      await controller.start();
      backend.error!('error_permission');
      expect(controller.showSettings, isTrue);
      expect(controller.message, backend.permissionHelp);
    },
  );
  test(
    'stop menunggu final setelah done, tidak menyimpan teks sementara',
    () async {
      await controller.start();
      backend.emit('makan');
      await controller.stop();
      expect(controller.phase, VoicePhase.finishing);
      expect(finals, isEmpty);
      backend.emit('makan 35 ribu', finalResult: true);
      expect(finals, ['makan 35 ribu']);
    },
  );
  testWidgets(
    'done tanpa final membersihkan interim; sesi berikutnya tetap bisa selesai',
    (tester) async {
      await controller.start();
      backend.emit('sementara');
      backend.done!();
      await tester.pump(const Duration(seconds: 3));
      expect(controller.interim, isEmpty);
      expect(finals, isEmpty);
      expect(controller.phase, VoicePhase.idle);
      await controller.start();
      backend.done!();
      backend.emit('gaji 8 juta', finalResult: true);
      expect(finals, ['gaji 8 juta']);
    },
  );
}
