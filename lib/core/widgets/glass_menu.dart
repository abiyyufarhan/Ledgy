import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class GlassMenuEntry<T> {
  const GlassMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });
  final T? value;
  final Widget label;
  final Widget? icon;
  final bool enabled;
}

/// A non-null result can deliberately contain null (e.g. "Semua akun").
/// Dismissing the menu instead returns no result and never changes a filter.
class GlassMenuSelection<T> {
  const GlassMenuSelection(this.value);
  final T? value;
}

class GlassMenuSurface extends StatelessWidget {
  const GlassMenuSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.menuPadding),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  static final _filter = ImageFilter.blur(
    sigmaX: AppTheme.glassBlur,
    sigmaY: AppTheme.glassBlur,
  );

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: _filter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glassMenuFill,
            borderRadius: BorderRadius.circular(AppTheme.panelRadius),
            border: Border.all(color: AppTheme.glassMenuBorder),
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    ),
  );
}

Future<GlassMenuSelection<T>?> showGlassMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<GlassMenuEntry<T>> entries,
  T? selectedValue,
  Widget? header,
  double width = AppTheme.menuWidth,
  bool coverAnchor = false,
}) {
  final anchor = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay!.context.findRenderObject()!
          as RenderBox;
  final rect =
      anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
  final theme = Theme.of(context);
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<GlassMenuSelection<T>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup menu',
    barrierColor: Colors.transparent,
    transitionDuration: reducedMotion ? Duration.zero : AppTheme.menuDuration,
    pageBuilder: (context, animation, secondaryAnimation) => Theme(
      data: theme,
      child: _GlassMenuPage<T>(
        anchor: rect,
        entries: entries,
        selectedValue: selectedValue,
        header: header,
        width: width,
        coverAnchor: coverAnchor,
        animation: animation,
      ),
    ),
    transitionBuilder: (_, _, _, child) => child,
  );
}

class _GlassMenuPage<T> extends StatelessWidget {
  const _GlassMenuPage({
    required this.anchor,
    required this.entries,
    required this.selectedValue,
    required this.header,
    required this.width,
    required this.coverAnchor,
    required this.animation,
  });
  final Rect anchor;
  final List<GlassMenuEntry<T>> entries;
  final T? selectedValue;
  final Widget? header;
  final double width;
  final bool coverAnchor;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final safe = media.padding;
    final rowHeight =
        AppTheme.menuRowHeight * math.max(1.0, media.textScaler.scale(16) / 16);
    final headerHeight = header == null
        ? 0.0
        : AppTheme.profileButtonSize + AppTheme.fieldSpacing;
    final availableHeight = math.max(
      0.0,
      media.size.height -
          safe.top -
          safe.bottom -
          media.viewInsets.bottom -
          AppTheme.menuMargin * 2,
    );
    final menuHeight = math.min(
      availableHeight,
      math.min(
        AppTheme.menuMaxHeight,
        entries.length * rowHeight + headerHeight + AppTheme.menuPadding * 2,
      ),
    );
    final menuWidth = math.min(
      width,
      media.size.width - safe.left - safe.right - AppTheme.menuMargin * 2,
    );
    final left = (anchor.right - menuWidth).clamp(
      safe.left + AppTheme.menuMargin,
      media.size.width - safe.right - AppTheme.menuMargin - menuWidth,
    );
    final preferredTop = coverAnchor
        ? anchor.top
        : anchor.bottom + AppTheme.menuMargin;
    final top = preferredTop.clamp(
      safe.top + AppTheme.menuMargin,
      math.max(
        safe.top + AppTheme.menuMargin,
        media.size.height -
            safe.bottom -
            media.viewInsets.bottom -
            AppTheme.menuMargin -
            menuHeight,
      ),
    );
    final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            FocusScope.of(context).nextFocus(),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            FocusScope.of(context).previousFocus(),
      },
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top.toDouble(),
            width: menuWidth,
            height: menuHeight,
            child: FadeTransition(
              opacity: curve,
              child: Align(
                alignment: Alignment.topRight,
                child: SizeTransition(
                  sizeFactor: curve,
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: menuWidth,
                    height: menuHeight,
                    child: GlassMenuSurface(
                      child: Column(
                        children: [
                          if (header != null) ...[
                            SizedBox(
                              height: AppTheme.profileButtonSize,
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.panelRadius,
                                ),
                                child: header,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppTheme.compactSpacing,
                                vertical: AppTheme.compactSpacing,
                              ),
                              child: Divider(
                                height: 0,
                                color: AppTheme.glassMenuBorder,
                              ),
                            ),
                          ],
                          Expanded(
                            child: FocusTraversalGroup(
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemExtent: rowHeight,
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  final selected = entry.value == selectedValue;
                                  return Semantics(
                                    selected: selected,
                                    button: true,
                                    child: Material(
                                      color: selected
                                          ? theme.colorScheme.primary
                                                .withValues(alpha: .16)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.fieldSpacing,
                                      ),
                                      child: InkWell(
                                        autofocus: index == 0,
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.fieldSpacing,
                                        ),
                                        onTap: !entry.enabled
                                            ? null
                                            : () => Navigator.pop(
                                                context,
                                                GlassMenuSelection<T>(
                                                  entry.value,
                                                ),
                                              ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppTheme.menuRowPadding,
                                          ),
                                          child: IconTheme(
                                            data: IconThemeData(
                                              size: AppTheme.navigationIconSize,
                                              color: entry.enabled
                                                  ? theme.colorScheme.onSurface
                                                  : theme.disabledColor,
                                            ),
                                            child: DefaultTextStyle(
                                              style: theme.textTheme.titleSmall!
                                                  .copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: entry.enabled
                                                        ? theme
                                                              .colorScheme
                                                              .onSurface
                                                        : theme.disabledColor,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              child: Row(
                                                children: [
                                                  if (entry.icon != null) ...[
                                                    entry.icon!,
                                                    const SizedBox(
                                                      width: AppTheme
                                                          .menuRowPadding,
                                                    ),
                                                  ],
                                                  Expanded(child: entry.label),
                                                  if (selected)
                                                    const Icon(
                                                      Icons.check_rounded,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
