import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/settings_row.dart';
import '../domain/app_lock.dart';
import 'lock_providers.dart';

class SecuritySettings extends ConsumerStatefulWidget {
  const SecuritySettings({super.key});
  @override
  ConsumerState<SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends ConsumerState<SecuritySettings>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(appLockProvider).refreshBiometrics());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(appLockProvider).refreshBiometrics());
    }
  }

  Future<void> _password({bool remove = false}) async {
    final lock = ref.read(appLockProvider);
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PasswordSettingsDialog(lock: lock, remove: remove),
    );
  }

  Future<void> _biometric(bool value) async {
    final lock = ref.read(appLockProvider);
    if (lock.passwordEnabled) {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PasswordSettingsDialog(lock: lock, biometric: value),
      );
    } else {
      await lock.configure(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLockChangesProvider);
    final lock = ref.watch(appLockProvider);
    final busy = !lock.ready || lock.authenticating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTheme.sectionSpacing),
        Text(
          'Keamanan & privasi',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.fieldSpacing),
        SettingsRow(
          icon: Icons.password_outlined,
          title: 'Password',
          subtitle: 'Kunci Ledgy dengan password 8–128 karakter. Mendukung A–Z, a–z, 0–9, dan simbol.',
          trailing: Wrap(
            spacing: AppTheme.compactSpacing,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (lock.passwordEnabled)
                TextButton(
                  onPressed: busy ? null : () => _password(),
                  child: const Text('Ubah password'),
                ),
              Semantics(
                label: 'Aktifkan password Ledgy',
                child: Switch.adaptive(
                  key: const ValueKey('password-toggle'),
                  value: lock.passwordEnabled,
                  onChanged: busy ? null : (value) => _password(remove: !value),
                ),
              ),
            ],
          ),
        ),
        SettingsRow(
          icon: Icons.fingerprint,
          title: 'Biometrik',
          subtitle: lock.biometricAvailable == null
              ? 'Memeriksa dukungan biometrik perangkat…'
              : lock.biometricAvailable == false
              ? lock.biometricEnabled
                    ? 'Biometrik tidak tersedia. Kunci perangkat sebelumnya tetap tersimpan; Anda dapat menonaktifkannya atau menambahkan password.'
                    : 'Biometrik tidak tersedia atau belum disiapkan pada perangkat ini.'
              : Platform.isWindows
              ? 'Sensor biometrik tersedia. Windows Hello juga dapat menawarkan PIN perangkat.'
              : 'Gunakan sidik jari atau pengenalan wajah yang sudah terdaftar di perangkat.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Periksa biometrik',
                onPressed: busy || lock.biometricAvailable == null
                    ? null
                    : lock.refreshBiometrics,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              Semantics(
                label: 'Aktifkan biometrik Ledgy',
                child: Switch.adaptive(
                  key: const ValueKey('biometric-toggle'),
                  value: lock.biometricEnabled,
                  // Old settings may be disabled even after a sensor disconnect.
                  onChanged:
                      busy ||
                          (lock.biometricAvailable != true &&
                              !lock.biometricEnabled)
                      ? null
                      : _biometric,
                ),
              ),
            ],
          ),
        ),
        if (lock.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              lock.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (lock.enabled)
          SettingsRow(
            icon: Icons.lock_outline,
            title: 'Kunci sekarang',
            subtitle: lock.passwordEnabled && lock.biometricEnabled
                ? 'Buka kembali dengan password atau biometrik. Aplikasi juga terkunci setelah kembali dari latar belakang.'
                : 'Verifikasi diperlukan saat dibuka dan setelah kembali dari latar belakang.',
            onTap: busy ? null : lock.lockNow,
            trailing: const Icon(Icons.chevron_right),
          ),
        const SizedBox(height: AppTheme.fieldSpacing),
        const SettingsRow(
          icon: Icons.privacy_tip_outlined,
          title: 'Privasi data',
          subtitle: 'Ledgy tidak mengirim transaksi ke layanan analitik. Sinkronisasi hanya melalui akun Anda. CSV berisi data terbuka; simpan di tempat yang aman.',
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class PasswordSettingsDialog extends StatefulWidget {
  const PasswordSettingsDialog({
    super.key,
    required this.lock,
    this.remove = false,
    this.biometric,
  });
  final AppLock lock;
  final bool remove;
  final bool? biometric;
  @override
  State<PasswordSettingsDialog> createState() => _PasswordSettingsDialogState();
}

class _PasswordSettingsDialogState extends State<PasswordSettingsDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _visible = false;
  String? _error;
  bool get _creating => !widget.remove && widget.biometric == null;

  Future<void> _save() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final accepted = widget.biometric != null
        ? await widget.lock.configure(
            widget.biometric!,
            password: _current.text,
          )
        : await widget.lock.setPassword(
            _creating ? _password.text : null,
            currentPassword: _current.text,
          );
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = widget.lock.error ?? 'Perubahan belum berhasil. Coba lagi.';
      });
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String? Function(String?) validator,
  ) => TextFormField(
    controller: controller,
    enabled: !_busy,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    decoration: InputDecoration(labelText: label),
    validator: validator,
    onFieldSubmitted: (_) => _busy ? null : _save(),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.biometric != null
            ? '${widget.biometric! ? 'Aktifkan' : 'Nonaktifkan'} biometrik'
            : widget.remove
            ? 'Nonaktifkan password'
            : widget.lock.passwordEnabled
            ? 'Ubah password'
            : 'Buat password Ledgy',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_creating) ...[
                  const Text(
                    'Password ini hanya untuk membuka Ledgy di perangkat ini, terpisah dari password akun. Simpan password Anda; password yang terlupa tidak dapat ditampilkan kembali.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.lock.passwordEnabled) ...[
                  _field(
                    _current,
                    'Password saat ini',
                    (value) => value == null || value.isEmpty
                        ? 'Masukkan password saat ini.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_creating) ...[
                  _field(
                    _password,
                    'Password baru',
                    (value) =>
                        value == null ||
                            value.runes.length < 8 ||
                            value.runes.length > 128
                        ? 'Gunakan 8–128 karakter.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    _confirmation,
                    'Konfirmasi password',
                    (value) => value != _password.text
                        ? 'Konfirmasi password belum sama.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  label: Text(
                    _visible ? 'Sembunyikan password' : 'Tampilkan password',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }
}
