import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../branding/ledgy_mark.dart';
import '../theme/app_theme.dart';

class SidebarDestination {
  const SidebarDestination(
    this.path,
    this.label,
    this.icon, {
    this.children = const [],
  });
  final String path;
  final String label;
  final IconData icon;
  final List<SidebarSubdestination> children;
}

class SidebarSubdestination {
  const SidebarSubdestination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

TextStyle? _sidebarLabelStyle(BuildContext context, bool selected) =>
    Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: AppTheme.sidebarLabelSize,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: selected ? AppTheme.sidebarText : AppTheme.mutedText,
    );

/// Hover reveals a fixed-width, cached surface. Only its outer clip changes;
/// destinations keep their layout and the page is never resized by the reveal.
class LedgySidebar extends StatefulWidget {
  const LedgySidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAddTransaction,
    this.onPinnedChanged,
    this.initiallyPinned = false,
    this.profileBuilder,
    this.selectedSubpath,
    this.onSubSelected,
  });

  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAddTransaction;
  final ValueChanged<bool>? onPinnedChanged;
  final bool initiallyPinned;
  final Widget Function(Animation<double> labels)? profileBuilder;
  final String? selectedSubpath;
  final ValueChanged<String>? onSubSelected;

  @override
  State<LedgySidebar> createState() => _LedgySidebarState();
}

class _LedgySidebarState extends State<LedgySidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTheme.sidebarDuration,
  );
  late final CurvedAnimation _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );
  late final Animation<double> _labels = _reveal.drive(
    CurveTween(curve: const Interval(.15, .8, curve: Curves.easeOut)),
  );
  final _focus = FocusNode(debugLabel: 'Ledgy sidebar');
  Timer? _exitTimer;
  bool _hovered = false;
  bool _keyboardFocused = false;
  bool _pinned = false;
  bool _reduceMotion = false;
  final _openPaths = <String>{};

  bool get _expanded => _hovered || _keyboardFocused || _pinned;

  @override
  void initState() {
    super.initState();
    _pinned = widget.initiallyPinned;
    _openSelectedSubmenu();
    if (_pinned) _controller.value = 1;
  }

  void _openSelectedSubmenu() {
    for (final destination in widget.destinations) {
      if (destination.children.any(
        (child) => child.path == widget.selectedSubpath,
      )) {
        _openPaths.add(destination.path);
      }
    }
  }

  @override
  void didUpdateWidget(LedgySidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubpath != widget.selectedSubpath) {
      _openSelectedSubmenu();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = _expanded ? 1 : 0;
  }

  void _animate() {
    if (_reduceMotion) {
      _controller.value = _expanded ? 1 : 0;
    } else if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _enter() {
    _exitTimer?.cancel();
    _hovered = true;
    _animate();
  }

  void _leave() {
    _exitTimer?.cancel();
    _exitTimer = Timer(AppTheme.sidebarExitDelay, () {
      _hovered = false;
      _animate();
    });
  }

  void _focusChanged(bool focused) {
    _keyboardFocused = focused && !_hovered;
    _animate();
  }

  KeyEventResult _keyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _exitTimer?.cancel();
      _hovered = false;
      _keyboardFocused = false;
      setState(() => _pinned = false);
      widget.onPinnedChanged?.call(false);
      _focus.unfocus();
      _animate();
      return KeyEventResult.handled;
    }
    _keyboardFocused = true;
    _animate();
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _focus.dispose();
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemHeight = math.max(
      AppTheme.sidebarItemHeight,
      MediaQuery.textScalerOf(context).scale(AppTheme.sidebarLabelSize) * 1.4 +
          AppTheme.menuRowPadding,
    );
    final pinLabel = _pinned ? 'Lepas sematan sidebar' : 'Sematkan sidebar';
    final headerHeight = math.max(
      AppTheme.sidebarHeaderHeight,
      MediaQuery.textScalerOf(context).scale(16) * 1.5 +
          MediaQuery.textScalerOf(context).scale(11) * 1.4 +
          AppTheme.menuPadding,
    );
    return Focus(
      focusNode: _focus,
      onFocusChange: _focusChanged,
      onKeyEvent: _keyEvent,
      child: MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _leave(),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _reveal,
            builder: (context, child) => SizedBox(
              key: const ValueKey('sidebar-surface'),
              width:
                  AppTheme.sidebarCompactWidth +
                  (AppTheme.sidebarExpandedWidth -
                          AppTheme.sidebarCompactWidth) *
                      _reveal.value,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: AppTheme.sidebarExpandedWidth,
                  maxWidth: AppTheme.sidebarExpandedWidth,
                  child: child,
                ),
              ),
            ),
            child: RepaintBoundary(
              child: Material(
                color: AppTheme.sidebarSurface,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: AppTheme.sidebarBorder),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.compactSpacing,
                        ),
                        child: SizedBox(
                          height: headerHeight,
                          child: Semantics(
                            button: true,
                            toggled: _pinned,
                            label: pinLabel,
                            child: Tooltip(
                              message: pinLabel,
                              child: InkWell(
                                key: const ValueKey('sidebar-pin'),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.sidebarItemRadius,
                                ),
                                hoverColor: AppTheme.sidebarHoverFill,
                                onTap: () {
                                  setState(() => _pinned = !_pinned);
                                  if (_pinned) _focus.requestFocus();
                                  widget.onPinnedChanged?.call(_pinned);
                                  _animate();
                                },
                                child: Row(
                                  children: [
                                    const SizedBox.square(
                                      dimension: AppTheme.minTouchTarget,
                                      child: Center(
                                        child: ExcludeSemantics(
                                          child: LedgyMark(
                                            size: AppTheme.sidebarLogoSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: FadeTransition(
                                        opacity: _labels,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: AppTheme.compactSpacing,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Ledgy',
                                                maxLines: 1,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color:
                                                          AppTheme.sidebarText,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              Text(
                                                'Versi ${AppTheme.sidebarVersion}',
                                                maxLines: 1,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: AppTheme.mutedText,
                                                    ),
                                              ),
                                            ],
                                          ),
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
                      if (widget.profileBuilder != null) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppTheme.fieldSpacing,
                          ),
                          child: Divider(color: AppTheme.sidebarBorder),
                        ),
                        widget.profileBuilder!(_labels),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppTheme.fieldSpacing,
                          ),
                          child: Divider(color: AppTheme.sidebarBorder),
                        ),
                      ],
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.compactSpacing,
                            vertical: AppTheme.compactSpacing,
                          ),
                          itemCount: widget.destinations.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppTheme.sidebarItemGap),
                          itemBuilder: (context, index) => Column(
                            children: [
                              _SidebarItem(
                                destination: widget.destinations[index],
                                selected: index == widget.selectedIndex,
                                labels: _labels,
                                reveal: _reveal,
                                height: itemHeight,
                                submenuExpanded: _openPaths.contains(
                                  widget.destinations[index].path,
                                ),
                                onTap: () {
                                  final destination =
                                      widget.destinations[index];
                                  if (destination.children.isNotEmpty) {
                                    setState(() {
                                      if (!_openPaths.remove(
                                        destination.path,
                                      )) {
                                        _openPaths.add(destination.path);
                                      }
                                    });
                                    _focus.requestFocus();
                                    _keyboardFocused = true;
                                    _animate();
                                  }
                                  if (index != widget.selectedIndex ||
                                      destination.children.isEmpty) {
                                    widget.onSelected(index);
                                  }
                                },
                              ),
                              if (_openPaths.contains(
                                widget.destinations[index].path,
                              ))
                                for (final child
                                    in widget.destinations[index].children)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppTheme.sidebarItemGap,
                                    ),
                                    child: _SidebarSubitem(
                                      destination: child,
                                      selected:
                                          child.path == widget.selectedSubpath,
                                      height: itemHeight,
                                      reveal: _reveal,
                                      labels: _labels,
                                      onTap: () => widget.onSubSelected?.call(
                                        child.path,
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(color: AppTheme.sidebarBorder, height: 1),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.compactSpacing,
                            AppTheme.fieldSpacing,
                            AppTheme.compactSpacing,
                            AppTheme.pagePadding,
                          ),
                          child: _SidebarTransactionButton(
                            onPressed: widget.onAddTransaction,
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
    );
  }
}

class _SidebarSubitem extends StatelessWidget {
  static const _expandedWidth =
      AppTheme.sidebarExpandedWidth -
      AppTheme.compactSpacing * 2 -
      AppTheme.sidebarSubitemIndent;
  const _SidebarSubitem({
    required this.destination,
    required this.selected,
    required this.height,
    required this.onTap,
    required this.reveal,
    required this.labels,
  });
  final SidebarSubdestination destination;
  final bool selected;
  final double height;
  final VoidCallback onTap;
  final Animation<double> reveal;
  final Animation<double> labels;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: destination.label,
    child: AnimatedBuilder(
      animation: reveal,
      builder: (context, child) => TooltipVisibility(
        visible: reveal.value < .01,
        child: Tooltip(
          message: destination.label,
          child: Padding(
            padding: EdgeInsets.only(
              left: AppTheme.sidebarSubitemIndent * reveal.value,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: height,
                width:
                    AppTheme.minTouchTarget +
                    (_expandedWidth - AppTheme.minTouchTarget) * reveal.value,
                child: Material(
                  color: selected
                      ? AppTheme.sidebarSelectedFill
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    AppTheme.sidebarItemRadius,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('sidebar-subdestination-${destination.path}'),
                    onTap: onTap,
                    hoverColor: AppTheme.sidebarHoverFill,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: _expandedWidth,
                        maxWidth: _expandedWidth,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.menuRowPadding,
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: AppTheme.navigationIconSize,
                child: Center(
                  child: Icon(
                    destination.icon,
                    key: ValueKey('sidebar-subicon-${destination.path}'),
                    size: AppTheme.sidebarSubitemIconSize,
                    color: selected ? AppTheme.sidebarText : AppTheme.mutedText,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.compactSpacing),
              Expanded(
                child: FadeTransition(
                  opacity: labels,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sidebarLabelStyle(context, selected),
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

class _SidebarTransactionButton extends StatefulWidget {
  const _SidebarTransactionButton({required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<_SidebarTransactionButton> createState() =>
      _SidebarTransactionButtonState();
}

class _SidebarTransactionButtonState extends State<_SidebarTransactionButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final expanded = _hovered || _focused;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTheme.sidebarDuration;
    final width = AppTheme.sidebarExpandedWidth - AppTheme.compactSpacing * 2;
    final height = math.max(
      AppTheme.minTouchTarget,
      MediaQuery.textScalerOf(context).scale(AppTheme.sidebarLabelSize) * 1.4 +
          AppTheme.menuRowPadding,
    );
    return RepaintBoundary(
      child: Semantics(
        label: 'Tambah transaksi',
        button: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            key: const ValueKey('sidebar-transaction-surface'),
            width: expanded ? width : AppTheme.minTouchTarget,
            height: height,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: Material(
              color: AppTheme.sidebarAddFill,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(AppTheme.sidebarItemRadius),
              child: InkWell(
                key: const ValueKey('sidebar-add-transaction'),
                onTap: widget.onPressed,
                onFocusChange: (value) => setState(() => _focused = value),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: width,
                    maxWidth: width,
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          const SizedBox(
                            width: AppTheme.minTouchTarget,
                            child: Center(child: _TransactionPlus()),
                          ),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: expanded ? 1 : 0,
                              duration: duration,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: AppTheme.compactSpacing,
                                  right: AppTheme.compactSpacing,
                                ),
                                child: Text(
                                  'Transaksi',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontSize: AppTheme.sidebarLabelSize,
                                        color: AppTheme.sidebarText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
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
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.labels,
    required this.reveal,
    required this.height,
    required this.onTap,
    this.submenuExpanded = false,
  });
  final SidebarDestination destination;
  final bool selected;
  final Animation<double> labels;
  final Animation<double> reveal;
  final double height;
  final VoidCallback onTap;
  final bool submenuExpanded;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: destination.label,
    child: AnimatedBuilder(
      animation: reveal,
      builder: (context, child) => TooltipVisibility(
        visible: reveal.value < .01,
        child: Tooltip(
          message: destination.label,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width:
                  AppTheme.minTouchTarget +
                  (AppTheme.sidebarExpandedWidth -
                          AppTheme.sidebarCompactWidth) *
                      reveal.value,
              height: height,
              child: Material(
                color: selected
                    ? AppTheme.sidebarSelectedFill
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppTheme.sidebarItemRadius,
                  ),
                  side: BorderSide(
                    color: selected
                        ? AppTheme.sidebarSelectedBorder
                        : Colors.transparent,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('sidebar-destination-${destination.path}'),
                  onTap: onTap,
                  hoverColor: AppTheme.sidebarHoverFill,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth:
                          AppTheme.sidebarExpandedWidth -
                          AppTheme.compactSpacing * 2,
                      maxWidth:
                          AppTheme.sidebarExpandedWidth -
                          AppTheme.compactSpacing * 2,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: AppTheme.minTouchTarget,
              child: Center(
                child: Icon(
                  destination.icon,
                  key: ValueKey('sidebar-icon-${destination.path}'),
                  size: AppTheme.navigationIconSize,
                  color: selected ? AppTheme.sidebarText : AppTheme.mutedText,
                ),
              ),
            ),
            Expanded(
              child: FadeTransition(
                opacity: labels,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppTheme.compactSpacing,
                    right: AppTheme.menuRowPadding,
                  ),
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sidebarLabelStyle(context, selected),
                  ),
                ),
              ),
            ),
            if (destination.children.isNotEmpty)
              FadeTransition(
                opacity: labels,
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: AppTheme.compactSpacing,
                  ),
                  child: Icon(
                    submenuExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: AppTheme.mutedText,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TransactionPlus extends StatelessWidget {
  const _TransactionPlus();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppTheme.navigationIconSize,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (final size in const [
          Size(AppTheme.sidebarPlusLength, AppTheme.sidebarPlusStroke),
          Size(AppTheme.sidebarPlusStroke, AppTheme.sidebarPlusLength),
        ])
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.sidebarText,
              borderRadius: BorderRadius.circular(AppTheme.sidebarPlusRadius),
            ),
            child: SizedBox.fromSize(size: size),
          ),
      ],
    ),
  );
}
