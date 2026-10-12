import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/platform_providers.dart';
import '../../../core/widgets/expanding_glass_button.dart';
import '../../../core/widgets/glass_menu.dart';
import '../domain/auth_repository.dart';
import '../../sync/presentation/sync_providers.dart';
import 'saver_profile_widgets.dart';

class ProfileMenu extends ConsumerStatefulWidget {
  const ProfileMenu({super.key}) : labels = null, compact = false;
  const ProfileMenu.sidebar({super.key, required this.labels})
    : compact = false;
  const ProfileMenu.compact({super.key}) : labels = null, compact = true;
  final Animation<double>? labels;
  final bool compact;
  @override
  ConsumerState<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends ConsumerState<ProfileMenu> {
  final _anchor = GlobalKey();
  bool _opened = false;
  void _openProfile() => context.push('/profile');

  Widget _avatar(CloudUser? user) {
    final photo = user?.avatarUrl;
    final size = widget.labels == null
        ? AppTheme.avatarSize
        : AppTheme.sidebarAvatarSize;
    final fallback = ColoredBox(
      color: AppTheme.profileAvatarFill,
      child: const Center(
        child: Icon(Icons.person_rounded, size: AppTheme.navigationIconSize),
      ),
    );
    return RepaintBoundary(
      key: widget.labels != null
          ? const ValueKey('sidebar-profile-avatar')
          : null,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          clipBehavior: Clip.antiAlias,
          child: photo == null || photo.isEmpty
              ? fallback
              : Image.network(
                  photo,
                  width: size,
                  height: size,
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  filterQuality: FilterQuality.high,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    if (_opened) return;
    final user = ref.read(authRepositoryProvider).currentUser;
    final loggedIn = ref.read(authRepositoryProvider).currentUser != null;
    setState(() => _opened = true);
    final selected = await showGlassMenu<String>(
      context: context,
      anchorContext: _anchor.currentContext!,
      coverAnchor: widget.labels == null,
      width: AppTheme.profileExpandedWidth,
      header: Row(
        children: [
          const SizedBox(width: AppTheme.menuRowPadding),
          Expanded(
            child: Text(
              user?.displayName ?? 'Daftar / Login',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppTheme.compactSpacing),
          _avatar(user),
        ],
      ),
      entries: [
        GlassMenuEntry(
          value: 'account',
          icon: Icon(
            loggedIn ? Icons.account_balance_wallet_outlined : Icons.login,
          ),
          label: Text(loggedIn ? 'Tambah aset' : 'Login'),
        ),
        const GlassMenuEntry(
          value: 'settings',
          icon: Icon(Icons.settings_outlined),
          label: Text('Setting'),
        ),
        const GlassMenuEntry(
          value: 'exit',
          icon: Icon(Icons.power_settings_new),
          label: Text('Exit'),
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _opened = false);
    switch (selected?.value) {
      case 'account':
        context.go(
          loggedIn
              ? '/asset-setup'
              : Uri(
                  path: '/login',
                  queryParameters: {'mode': 'register', 'next': '/asset-setup'},
                ).toString(),
        );
      case 'settings':
        context.go('/settings');
      case 'exit':
        await ref.read(exitApplicationProvider)();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user =
        ref.watch(cloudUserProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    if (widget.compact) {
      return IconButton(
        key: _anchor,
        tooltip: 'Profil Ledgy',
        onPressed: _openProfile,
        icon: _avatar(user),
      );
    }
    if (widget.labels != null) {
      final name = user?.displayName ?? 'Daftar / Login';
      final height = math.max(
        AppTheme.sidebarProfileHeight,
        MediaQuery.textScalerOf(context).scale(AppTheme.sidebarLabelSize) * 3 +
            AppTheme.fieldSpacing,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.compactSpacing,
        ),
        child: Semantics(
          label:
              'Profil $name, ${user?.saverProfile?.label ?? 'Profil belum dipilih'}',
          button: true,
          child: InkWell(
            key: _anchor,
            onTap: _openProfile,
            borderRadius: BorderRadius.circular(AppTheme.sidebarItemRadius),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  SizedBox(
                    width: AppTheme.minTouchTarget,
                    child: Center(child: _avatar(user)),
                  ),
                  Expanded(
                    child: FadeTransition(
                      opacity: widget.labels!,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: AppTheme.compactSpacing,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontSize: AppTheme.sidebarLabelSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: AppTheme.menuPadding),
                            if (user?.saverProfile case final profile?)
                              SaverProfileBadge(profile: profile)
                            else
                              Text(
                                user == null
                                    ? 'Mode lokal'
                                    : 'Profil belum dipilih',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppTheme.mutedText),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  FadeTransition(
                    opacity: widget.labels!,
                    child: const Padding(
                      padding: EdgeInsets.all(AppTheme.compactSpacing),
                      child: Icon(
                        Icons.chevron_right,
                        size: AppTheme.navigationIconSize,
                        color: AppTheme.mutedText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.fieldSpacing,
        vertical: AppTheme.compactSpacing,
      ),
      child: IgnorePointer(
        ignoring: _opened,
        child: Opacity(
          opacity: _opened ? 0 : 1,
          child: ExpandingGlassButton(
            key: _anchor,
            tooltip: 'Profil Ledgy',
            label: user?.displayName ?? 'Daftar / Login',
            onPressed: _open,
            trailing: _avatar(user),
          ),
        ),
      ),
    );
  }
}
