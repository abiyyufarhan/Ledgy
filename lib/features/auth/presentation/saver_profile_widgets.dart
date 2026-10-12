import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/saver_profile.dart';

extension SaverProfileVisuals on SaverProfile {
  Color get color => switch (this) {
    SaverProfile.conservative => AppTheme.saverConservative,
    SaverProfile.moderate => AppTheme.saverModerate,
    SaverProfile.aggressive => AppTheme.saverAggressive,
    SaverProfile.opportunistic => AppTheme.saverOpportunistic,
    SaverProfile.impulsive => AppTheme.saverImpulsive,
  };

  // The exact profile color remains in the border/fill; brighten the text to
  // keep it legible on a dark translucent surface, including the blue badge.
  Color get textColor => Color.lerp(color, AppTheme.sidebarText, .55)!;
}

class SaverProfileBadge extends StatelessWidget {
  const SaverProfileBadge({super.key, required this.profile});
  final SaverProfile profile;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: profile.label,
    child: Semantics(
      label: profile.label,
      child: Container(
        key: ValueKey('saver-badge-${profile.code}'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.compactSpacing,
          vertical: AppTheme.menuPadding,
        ),
        decoration: BoxDecoration(
          color: profile.color.withValues(alpha: .28),
          border: Border.all(color: profile.color),
          borderRadius: BorderRadius.circular(AppTheme.sidebarBadgeRadius),
        ),
        child: Text(
          profile.shortLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: AppTheme.sidebarBadgeFontSize,
            fontWeight: FontWeight.w700,
            color: profile.textColor,
          ),
        ),
      ),
    ),
  );
}

/// A form field so signup cannot silently assign a saver type to the user.
class SaverProfileField extends FormField<SaverProfile> {
  SaverProfileField({
    super.key,
    super.initialValue,
    super.enabled = true,
    required ValueChanged<SaverProfile> onChanged,
    super.validator,
  }) : super(
         builder: (state) => LayoutBuilder(
           builder: (context, constraints) {
             final columns =
                 constraints.maxWidth >= 320 &&
                     MediaQuery.textScalerOf(context).scale(14) < 21
                 ? 2
                 : 1;
             final width =
                 (constraints.maxWidth -
                     AppTheme.compactSpacing * (columns - 1)) /
                 columns;
             return Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   'Profil penabung',
                   style: Theme.of(context).textTheme.titleSmall,
                 ),
                 const SizedBox(height: AppTheme.compactSpacing),
                 Wrap(
                   spacing: AppTheme.compactSpacing,
                   runSpacing: AppTheme.compactSpacing,
                   children: [
                     for (final profile in SaverProfile.values)
                       Semantics(
                         selected: state.value == profile,
                         child: SizedBox(
                           width: width,
                           child: OutlinedButton(
                             key: ValueKey('saver-choice-${profile.code}'),
                             onPressed: state.widget.enabled
                                 ? () {
                                     state.didChange(profile);
                                     onChanged(profile);
                                   }
                                 : null,
                             style: OutlinedButton.styleFrom(
                               minimumSize: const Size(
                                 0,
                                 AppTheme.minTouchTarget,
                               ),
                               foregroundColor: profile.textColor,
                               backgroundColor: profile.color.withValues(
                                 alpha: state.value == profile ? .40 : .18,
                               ),
                               side: BorderSide(
                                 color: profile.color,
                                 width: state.value == profile ? 2 : 1,
                               ),
                               shape: RoundedRectangleBorder(
                                 borderRadius: BorderRadius.circular(
                                   AppTheme.saverChoiceRadius,
                                 ),
                               ),
                             ),
                             child: Text(
                               profile.shortLabel,
                               textAlign: TextAlign.center,
                             ),
                           ),
                         ),
                       ),
                   ],
                 ),
                 if (state.value != null) ...[
                   const SizedBox(height: AppTheme.compactSpacing),
                   Text(
                     '${state.value!.label} — ${state.value!.description}',
                     style: Theme.of(context).textTheme.bodySmall,
                   ),
                 ],
                 if (state.hasError) ...[
                   const SizedBox(height: AppTheme.compactSpacing),
                   Text(
                     state.errorText!,
                     style: TextStyle(
                       color: Theme.of(context).colorScheme.error,
                     ),
                   ),
                 ],
               ],
             );
           },
         ),
       );
}
