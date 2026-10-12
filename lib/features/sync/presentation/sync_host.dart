import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sync_models.dart';
import 'sync_providers.dart';

/// SQLite retains pending writes through offline periods, sign-out, process
/// exits and Workmanager writes. Cloud requests run while the app is active.
class SyncHost extends ConsumerStatefulWidget {
  const SyncHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SyncHost> createState() => _SyncHostState();
}

class _SyncHostState extends ConsumerState<SyncHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _running = false;
  bool _again = false;
  bool _active = true;
  int _retrySeconds = 5;
  ProviderSubscription? _session;
  ProviderSubscription? _queue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = ref.listenManual(cloudUserProvider, (_, next) {
      if (!next.isLoading) _schedule(Duration.zero);
    }, fireImmediately: true);
    _queue = ref.listenManual(syncQueueProvider, (_, next) {
      if (next.hasValue) {
        unawaited(ref.read(syncServiceProvider).refreshLocalStatus());
        if (next.value!.pending > 0 &&
            ref.read(authRepositoryProvider).currentUser != null) {
          _schedule(const Duration(milliseconds: 1200));
        }
      }
    }, fireImmediately: true);
  }

  void _schedule(Duration delay) {
    if (!mounted || !_active) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (!mounted || !_active) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      final service = ref.read(syncServiceProvider);
      await service.sync();
      if (!mounted ||
          !_active ||
          ref.read(authRepositoryProvider).currentUser == null) {
        return;
      }
      if (service.status.phase == SyncPhase.synced) {
        _retrySeconds = 5;
        _schedule(
          _again
              ? const Duration(milliseconds: 1200)
              : const Duration(minutes: 1),
        );
      } else if (service.status.phase == SyncPhase.waiting &&
          service.status.message == 'Perubahan baru menunggu dikirim.') {
        _schedule(const Duration(milliseconds: 1200));
      } else {
        _schedule(Duration(seconds: _retrySeconds));
        _retrySeconds = (_retrySeconds * 2).clamp(5, 60);
      }
    } finally {
      _running = false;
      _again = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      ref.invalidate(syncQueueProvider);
      _schedule(Duration.zero);
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    _timer?.cancel();
    _session?.close();
    _queue?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
