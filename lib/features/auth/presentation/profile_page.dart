import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/platform_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/data/savings_goal_repository.dart';
import '../../local/presentation/local_providers.dart';
import '../../sync/presentation/sync_providers.dart';
import '../data/profile_actions.dart';
import '../domain/account_profile_repository.dart';
import '../domain/auth_repository.dart';
import 'saver_profile_widgets.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _busy = false;
  String? _error;

  void _login() => context.go('/login?mode=register&next=/asset-setup');

  AccountProfileRepository get _account {
    final auth = ref.read(authRepositoryProvider);
    if (auth is! AccountProfileRepository) {
      throw const AuthFailure('Layanan pengaturan akun belum tersedia.');
    }
    return auth as AccountProfileRepository;
  }

  Future<bool> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return true;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
      return true;
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Perubahan belum berhasil. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _editText(CloudUser user, {required bool email}) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ProfileTextDialog(
        email: email,
        initial: email ? user.email : user.displayName,
      ),
    );
    if (value == null || !mounted) return;
    await _run(
      () => email ? _account.updateEmail(value) : _account.updateName(value),
      email
          ? 'Permintaan perubahan email dikirim. Periksa tautan konfirmasi di email Anda.'
          : 'Nama berhasil diperbarui.',
    );
  }

  Future<void> _pickProfile(CloudUser user) async {
    final profile = await showDialog<SaverProfile>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Profil Penabung'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: SaverProfileField(
              initialValue: user.saverProfile,
              onChanged: (profile) => Navigator.pop(context, profile),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    if (profile == null || !mounted) return;
    await _run(
      () => ref.read(authRepositoryProvider).updateSaverProfile(profile),
      'Profil penabung diperbarui.',
    );
  }

  Future<bool> _confirm({required bool deleting}) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => _AccountConfirmationDialog(deleting: deleting),
      ) ==
      true;
  Future<void> _resetOrDelete({required bool deleting}) async {
    if (!await _confirm(deleting: deleting) || !mounted) return;
    final success = await _run(
      () async {
        final actions = ref.read(profileActionsProvider);
        if (deleting) {
          await actions.deleteAccount();
        } else {
          await actions.resetData();
        }
        if (mounted) {
          ref.invalidate(financeSnapshotProvider);
          ref.invalidate(savingsGoalsProvider);
        }
      },
      deleting
          ? 'Akun dihapus. Anda sekarang menggunakan mode lokal.'
          : 'Data berhasil direset. Akun tetap tersedia.',
    );
    if (success && deleting && mounted) context.go('/profile');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    final user = ref.watch(cloudUserProvider).value ?? auth.currentUser;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail Akun'),
          leading: IconButton(
            tooltip: 'Kembali',
            onPressed: _busy
                ? null
                : () => context.canPop() ? context.pop() : context.go('/'),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.pagePadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(child: _ProfileAvatar(user: user)),
                    const SizedBox(height: 32),
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      Text(
                        _error!,
                        key: const ValueKey('profile-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Informasi Akun', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _ProfileSection(
                      children: [
                        _ProfileRow(
                          icon: Icons.person_rounded,
                          color: theme.colorScheme.primary,
                          title: user?.displayName ?? 'Mode lokal',
                          subtitle: 'Nama',
                          onTap: _busy
                              ? null
                              : user == null
                              ? _login
                              : () => _editText(user, email: false),
                        ),
                        _ProfileRow(
                          icon: Icons.mail_rounded,
                          color: theme.colorScheme.primary,
                          title: user?.email ?? 'Belum masuk',
                          subtitle: 'Email',
                          onTap: _busy
                              ? null
                              : user == null
                              ? _login
                              : () => _editText(user, email: true),
                        ),
                        _ProfileRow(
                          key: const ValueKey('profile-saver-row'),
                          icon: Icons.savings_rounded,
                          color:
                              user?.saverProfile?.color ??
                              const Color(0xFFFBBF24),
                          title:
                              user?.saverProfile?.label ??
                              'Pilih profil penabung',
                          subtitle: 'Profil Penabung',
                          onTap: _busy
                              ? null
                              : user == null
                              ? _login
                              : () => _pickProfile(user),
                        ),
                        _ProfileRow(
                          icon: Icons.logout_rounded,
                          color: theme.colorScheme.error,
                          title: 'Keluar',
                          subtitle: 'Keluar dari aplikasi',
                          onTap: _busy
                              ? null
                              : () => ref.read(exitApplicationProvider)(),
                        ),
                      ],
                    ),
                    if (user == null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const ValueKey('profile-login'),
                        onPressed: _busy ? null : _login,
                        icon: const Icon(Icons.login),
                        label: const Text('Daftar / Login'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Area Berbahaya', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _ProfileSection(
                      children: [
                        _ProfileRow(
                          key: const ValueKey('profile-reset'),
                          icon: Icons.delete_outline_rounded,
                          color: theme.colorScheme.error,
                          danger: true,
                          title: 'Reset Data',
                          subtitle: 'Reset data pengguna, akun tetap ada',
                          onTap: _busy
                              ? null
                              : () => _resetOrDelete(deleting: false),
                        ),
                        _ProfileRow(
                          key: const ValueKey('profile-delete'),
                          icon: Icons.delete_forever_rounded,
                          color: theme.colorScheme.error,
                          danger: true,
                          title: 'Hapus Akun',
                          subtitle: user == null
                              ? 'Masuk untuk menghapus akun'
                              : 'Hapus akun dan seluruh data pengguna',
                          onTap: _busy || user == null
                              ? null
                              : () => _resetOrDelete(deleting: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});
  final CloudUser? user;
  @override
  Widget build(BuildContext context) {
    final name = user?.displayName ?? '';
    final fallback = ColoredBox(
      color: user?.saverProfile?.color ?? AppTheme.profileAvatarFill,
      child: Center(
        child: name.isEmpty
            ? const Icon(Icons.person_rounded, color: Colors.white, size: 48)
            : Text(
                name.characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 44, color: Colors.white),
              ),
      ),
    );
    final photo = user?.avatarUrl;
    return SizedBox.square(
      dimension: 104,
      child: ClipOval(
        child: photo == null || photo.isEmpty
            ? fallback
            : Image.network(
                photo,
                fit: BoxFit.cover,
                cacheWidth: (104 * MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _ProfileTextDialog extends StatefulWidget {
  const _ProfileTextDialog({required this.email, required this.initial});
  final bool email;
  final String initial;
  @override
  State<_ProfileTextDialog> createState() => _ProfileTextDialogState();
}

class _ProfileTextDialogState extends State<_ProfileTextDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.email ? 'Ubah Email' : 'Ubah Nama'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.email
            ? TextInputType.emailAddress
            : TextInputType.name,
        textCapitalization: widget.email
            ? TextCapitalization.none
            : TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.email ? 'Email baru' : 'Nama',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Wajib diisi.';
          if (widget.email &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
            return 'Masukkan email yang valid.';
          }
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: const Text('Simpan'),
      ),
    ],
  );
}

class _AccountConfirmationDialog extends StatefulWidget {
  const _AccountConfirmationDialog({required this.deleting});
  final bool deleting;
  @override
  State<_AccountConfirmationDialog> createState() =>
      _AccountConfirmationDialogState();
}

class _AccountConfirmationDialogState
    extends State<_AccountConfirmationDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.deleting ? 'Hapus Akun?' : 'Reset Data?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.deleting
                ? 'Akun login dan seluruh data keuangannya akan dihapus permanen dari cloud dan perangkat ini. Tindakan ini tidak dapat dibatalkan.'
                : 'Transaksi, aset, kategori, anggaran, jadwal berulang, dan target tabungan akan direset. Akun login tetap ada. Perubahan reset akan disinkronkan ketika online.',
          ),
          if (widget.deleting) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Ketik HAPUS untuk melanjutkan',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Batal'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: widget.deleting && _controller.text.trim() != 'HAPUS'
            ? null
            : () => Navigator.pop(context, true),
        child: Text(widget.deleting ? 'Hapus Akun' : 'Reset Data'),
      ),
    ],
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(indent: 76, endIndent: 16),
          children[index],
        ],
      ],
    ),
  );
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    minVerticalPadding: 12,
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    ),
    title: Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: danger ? color : null, fontWeight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: danger ? color : AppTheme.mutedText),
      ),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 22),
    onTap: onTap,
  );
}
