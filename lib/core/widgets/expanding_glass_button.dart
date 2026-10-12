import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Translucent vector surface: no backdrop blur while hovering or scrolling.
/// The right edge and avatar remain fixed; only the label reveals to the left.
class ExpandingGlassButton extends StatefulWidget {
  const ExpandingGlassButton({
    super.key,
    required this.label,
    required this.trailing,
    required this.onPressed,
    this.size = AppTheme.profileButtonSize,
    this.expandedWidth = AppTheme.profileExpandedWidth,
    this.tooltip,
  });
  final String label;
  final Widget trailing;
  final VoidCallback onPressed;
  final double size;
  final double expandedWidth;
  final String? tooltip;

  @override
  State<ExpandingGlassButton> createState() => _ExpandingGlassButtonState();
}

class _ExpandingGlassButtonState extends State<ExpandingGlassButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final expanded = _hovered || _focused;
    final theme = Theme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTheme.hoverDuration;
    final width = widget.expandedWidth.clamp(
      widget.size,
      math.max(widget.size, MediaQuery.sizeOf(context).width * .75),
    );
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: widget.tooltip ?? widget.label,
        child: Tooltip(
          message: widget.tooltip ?? widget.label,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: expanded ? width.toDouble() : widget.size,
              height: widget.size,
              child: Material(
                color: AppTheme.glassMenuFill,
                clipBehavior: Clip.antiAlias,
                shape: const StadiumBorder(
                  side: BorderSide(color: AppTheme.glassMenuBorder),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onFocusChange: (value) => setState(() => _focused = value),
                  onTap: widget.onPressed,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final slot = math.min(
                        AppTheme.avatarSize,
                        constraints.maxHeight,
                      );
                      final inset = math.min(
                        (widget.size - slot) / 2,
                        math.max(0.0, (constraints.maxWidth - slot) / 2),
                      );
                      return Padding(
                        padding: EdgeInsets.all(inset),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRect(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.compactSpacing,
                                  ),
                                  child: AnimatedOpacity(
                                    duration: duration,
                                    opacity: expanded ? 1 : 0,
                                    child: Text(
                                      widget.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox.square(
                              dimension: slot,
                              child: Center(child: widget.trailing),
                            ),
                          ],
                        ),
                      );
                    },
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
