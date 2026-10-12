import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import 'lock_providers.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _covered = false;
  final _password = TextEditingController();
  bool _passwordVisible = false;

  Future<void> _unlockPassword() async {
    final password = _password.text;
    _password.clear();
    setState(() => _passwordVisible = false);
    await ref.read(appLockProvider).unlock(password: password);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(appLockProvider).initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider);
    if (state == AppLifecycleState.inactive) {
      setState(() => _covered = true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      lock.background();
      _password.clear();
      _passwordVisible = false;
      setState(() => _covered = true);
    } else if (state == AppLifecycleState.resumed) {
      lock.resume();
      setState(() => _covered = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLockChangesProvider);
    final lock = ref.watch(appLockProvider);
    final blocked = !lock.ready || lock.locked || (_covered && lock.enabled);
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: blocked,
          child: Offstage(
            offstage: blocked,
            child: TickerMode(enabled: !blocked, child: widget.child),
          ),
        ),
        if (blocked)
          Positioned.fill(
            child: PopScope(
              canPop: false,
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppTheme.pagePadding),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppTheme.authWidth,
                        ),
                        child: GlassPanel(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: AppTheme.profileButtonSize,
                              ),
                              const SizedBox(height: AppTheme.fieldSpacing),
                              Text(
                                'Ledgy terkunci',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: AppTheme.fieldSpacing),
                              Text(
                                lock.passwordEnabled && lock.biometricEnabled
                                    ? 'Gunakan password atau biometrik untuk membuka aplikasi.'
                                    : lock.passwordEnabled
                                    ? 'Masukkan password Ledgy untuk membuka aplikasi.'
                                    : 'Gunakan autentikasi perangkat untuk membuka aplikasi.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: AppTheme.fieldSpacing),
                              if (lock.error != null)
                                Text(lock.error!, textAlign: TextAlign.center),
                              if (!lock.ready && lock.error == null)
                                const Center(child: CircularProgressIndicator())
                              else if (!lock.ready)
                                FilledButton.icon(
                                  onPressed: lock.authenticating || _covered
                                      ? null
                                      : lock.initialize,
                                  icon: const Icon(Icons.fingerprint),
                                  label: Text(
                                    lock.authenticating
                                        ? 'Memverifikasi…'
                                        : 'Coba lagi',
                                  ),
                                ),
                              if (lock.ready && lock.passwordEnabled) ...[
                                const SizedBox(height: AppTheme.fieldSpacing),
                                TextField(
                                  key: const ValueKey('unlock-password'),
                                  controller: _password,
                                  enabled: !lock.authenticating && !_covered,
                                  obscureText: !_passwordVisible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  keyboardType: TextInputType.visiblePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Password Ledgy',
                                    suffixIcon: IconButton(
                                      tooltip: _passwordVisible
                                          ? 'Sembunyikan password'
                                          : 'Tampilkan password',
                                      onPressed: lock.authenticating || _covered
                                          ? null
                                          : () => setState(
                                              () => _passwordVisible =
                                                  !_passwordVisible,
                                            ),
                                      icon: Icon(
                                        _passwordVisible
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) =>
                                      lock.authenticating || _covered
                                      ? null
                                      : _unlockPassword(),
                                ),
                                const SizedBox(height: AppTheme.fieldSpacing),
                                FilledButton.icon(
                                  key: const ValueKey('unlock-password-button'),
                                  onPressed: lock.authenticating || _covered
                                      ? null
                                      : _unlockPassword,
                                  icon: const Icon(Icons.lock_open_outlined),
                                  label: Text(
                                    lock.authenticating
                                        ? 'Memverifikasi…'
                                        : 'Buka dengan password',
                                  ),
                                ),
                              ],
                              if (lock.ready && lock.biometricEnabled) ...[
                                const SizedBox(height: AppTheme.fieldSpacing),
                                OutlinedButton.icon(
                                  onPressed: lock.authenticating || _covered
                                      ? null
                                      : () => lock.unlock(),
                                  icon: const Icon(Icons.fingerprint),
                                  label: Text(
                                    lock.authenticating
                                        ? 'Memverifikasi…'
                                        : lock.passwordEnabled
                                        ? 'Buka dengan biometrik'
                                        : 'Buka Ledgy',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    super.dispose();
  }
}
