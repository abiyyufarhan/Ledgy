import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../sync/presentation/sync_providers.dart';
import '../domain/auth_repository.dart';
import 'saver_profile_widgets.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({
    super.key,
    this.registerInitially = false,
    this.next = '/settings',
  });
  final bool registerInitially;
  final String next;
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  late bool _register = widget.registerInitially;
  bool _busy = false;
  bool _obscure = true;
  bool _confirmationSent = false;
  String? _error;
  String? _info;
  SaverProfile? _saverProfile;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (_register) {
        final active = await repository.signUp(
          _email.text,
          _password.text,
          name: _name.text,
          saverProfile: _saverProfile,
        );
        if (!mounted) return;
        if (!active) {
          setState(() {
            _confirmationSent = true;
            _register = false;
            _info =
                'Jika alamat ini dapat didaftarkan, email konfirmasi telah dikirim. '
                'Buka tautannya, lalu kembali dan masuk dengan kata sandi Anda.';
          });
          return;
        }
      } else {
        await repository.signIn(_email.text, _password.text);
      }
      if (mounted) context.go(widget.next);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Belum dapat masuk. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_email.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendConfirmation(_email.text);
      if (mounted) {
        setState(
          () => _info = 'Periksa email Anda untuk tautan konfirmasi terbaru.',
        );
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cloudUserProvider, (_, next) {
      if (next.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(widget.next);
        });
      }
    });
    final configured = ref.watch(authRepositoryProvider).configured;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akun Ledgy'),
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.go('/settings'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.pagePadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTheme.authWidth),
              child: GlassPanel(
                child: Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.cloud_sync_outlined,
                        color: theme.colorScheme.primary,
                        size: theme.textTheme.displaySmall?.fontSize,
                      ),
                      const SizedBox(height: AppTheme.fieldSpacing),
                      Text(
                        'Keuangan Anda, di semua perangkat',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppTheme.fieldSpacing),
                      const Text(
                        'Masuk hanya untuk sinkronisasi. Pencatatan lokal tetap bisa digunakan tanpa akun.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.sectionSpacing),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Masuk')),
                          ButtonSegment(value: true, label: Text('Daftar')),
                        ],
                        selected: {_register},
                        onSelectionChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _register = value.first;
                                _error = null;
                                _form.currentState?.reset();
                                _saverProfile = null;
                              }),
                      ),
                      const SizedBox(height: AppTheme.sectionSpacing),
                      if (!configured) ...[
                        Text(
                          'Sinkronisasi cloud belum dikonfigurasi. Anda tetap dapat memakai mode lokal.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.fieldSpacing),
                      ],
                      AutofillGroup(
                        child: Column(
                          children: [
                            if (_register) ...[
                              TextFormField(
                                controller: _name,
                                enabled: !_busy,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(
                                  labelText: 'Nama profil',
                                ),
                              ),
                              const SizedBox(height: AppTheme.fieldSpacing),
                              SaverProfileField(
                                enabled: !_busy,
                                initialValue: _saverProfile,
                                onChanged: (value) =>
                                    setState(() => _saverProfile = value),
                                validator: (value) => value == null
                                    ? 'Pilih profil penabung Anda.'
                                    : null,
                              ),
                              const SizedBox(height: AppTheme.fieldSpacing),
                            ],
                            TextFormField(
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) =>
                                  RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(value?.trim() ?? '')
                                  ? null
                                  : 'Masukkan alamat email yang valid.',
                            ),
                            const SizedBox(height: AppTheme.fieldSpacing),
                            TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: [
                                _register
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Kata sandi',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Tampilkan kata sandi'
                                      : 'Sembunyikan kata sandi',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Masukkan kata sandi.'
                                  : _register && value.length < 8
                                  ? 'Gunakan minimal 8 karakter.'
                                  : null,
                              onFieldSubmitted:
                                  !_register && !_busy && configured
                                  ? (_) => _submit()
                                  : null,
                            ),
                            if (_register) ...[
                              const SizedBox(height: AppTheme.fieldSpacing),
                              TextFormField(
                                controller: _confirm,
                                enabled: !_busy,
                                obscureText: _obscure,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Ulangi kata sandi',
                                ),
                                validator: (value) => value == _password.text
                                    ? null
                                    : 'Kata sandi belum sama.',
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppTheme.fieldSpacing),
                        Text(
                          _error!,
                          key: const ValueKey('auth-error'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: AppTheme.fieldSpacing),
                        Text(_info!),
                      ],
                      const SizedBox(height: AppTheme.sectionSpacing),
                      FilledButton(
                        onPressed: _busy || !configured ? null : _submit,
                        child: Text(
                          _busy
                              ? 'Memproses…'
                              : _register
                              ? 'Daftar akun'
                              : 'Masuk dan sinkronkan',
                        ),
                      ),
                      if (_confirmationSent)
                        TextButton(
                          onPressed: _busy || !configured ? null : _resend,
                          child: const Text('Kirim ulang konfirmasi email'),
                        ),
                      TextButton(
                        onPressed: _busy ? null : () => context.go('/'),
                        child: const Text('Lanjut dalam mode lokal'),
                      ),
                      const Text(
                        'Saat masuk, data lokal akan digabung dengan data akun Anda.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _name.dispose();
    super.dispose();
  }
}
