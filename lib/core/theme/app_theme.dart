import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const pagePadding = 20.0;
  static const pageTitleFontSize = 24.0;
  static const fieldSpacing = 16.0;
  static const sectionSpacing = 24.0;
  static const panelRadius = 24.0;
  static const receiptFrameRadius = 16.0;
  static const dashboardPanelHeight = 400.0;
  static const dashboardMetricHeight = 168.0;
  static const glassBlur = 16.0;
  static const authWidth = 480.0;
  static const settingsWidth = 1080.0;
  static const settingsRowFill = Color(0xCC2D3440);
  static const settingsRowRadius = 6.0;
  static const settingsRowGap = 6.0;
  static const settingsRowVerticalPadding = 18.0;
  static const settingsRowIconSize = 26.0;
  static const settingsDescriptionGap = 3.0;
  static const settingsStackBreakpoint = 430.0;
  static const hoverDuration = Duration(milliseconds: 160);
  static const toolbarHeight = 72.0;
  static const profileButtonSize = 48.0;
  static const minTouchTarget = 48.0;
  static const sidebarBreakpoint = 700.0;
  static const sidebarCompactWidth = 64.0;
  static const sidebarExpandedWidth = 232.0;
  static const sidebarItemHeight = 48.0;
  static const sidebarHeaderHeight = 64.0;
  static const sidebarItemRadius = 12.0;
  static const sidebarItemGap = 4.0;
  static const sidebarDividerWidth = 1.0;
  static const sidebarLabelSize = 14.0;
  static const sidebarSubitemIndent = 24.0;
  static const sidebarSubitemIconSize = 20.0;
  static const sidebarDuration = Duration(milliseconds: 240);
  static const sidebarExitDelay = Duration(milliseconds: 120);
  static const sidebarSurface = Color(0xFF0A1422);
  static const sidebarBorder = Color(0xFF243247);
  static const sidebarSelectedFill = Color(0xFF152439);
  static const sidebarSelectedBorder = Color(0xFF4B74B3);
  static const sidebarHoverFill = Color(0xFF132032);
  static const sidebarText = Color(0xFFF3F7FF);
  static const sidebarAddFill = Color(0xFF304578);
  static const sidebarPlusLength = 22.0;
  static const sidebarPlusStroke = 3.0;
  static const sidebarPlusRadius = 2.0;
  static const sidebarVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '1.0.0',
  );
  static const sidebarLogoSize = 32.0;
  static const sidebarAvatarSize = 40.0;
  static const sidebarProfileHeight = 88.0;
  static const sidebarBadgeFontSize = 11.0;
  static const sidebarBadgeRadius = 5.0;
  static const saverChoiceRadius = 12.0;
  static const saverConservative = Color(0xFF1E56A0);
  static const saverModerate = Color(0xFF2E7D32);
  static const saverAggressive = Color(0xFFE65100);
  static const saverOpportunistic = Color(0xFF7B1FA2);
  static const saverImpulsive = Color(0xFFFBC02D);
  static const profileExpandedWidth = 260.0;
  static const printButtonSize = 56.0;
  static const printExpandedWidth = 150.0;
  static const avatarSize = 32.0;
  static const navigationIconSize = 24.0;
  static const menuDuration = Duration(milliseconds: 160);
  static const menuWidth = 280.0;
  static const menuMaxHeight = 420.0;
  static const menuRowHeight = 48.0;
  static const menuPadding = 4.0;
  static const menuRowPadding = 12.0;
  static const menuMargin = 8.0;
  static const glassMenuFill = Color(0xBD344051);
  static const glassMenuBorder = Color(0x99FFFFFF);
  static const profileAvatarFill = Color(0xFF304578);
  static const compactSpacing = 8.0;
  static const budgetTabHeight = 64.0;
  static const floatingBottomSpace = 100.0;
  static const mutedText = Color(0xFFB8C4D8);
  static const privacySurface = Color(0xFF071426);
  static const transactionSummaryFill = Color(0xFF102747);
  static const transactionIncome = Color(0xFF4ADE80);
  static const transactionExpense = Color(0xFFFF7185);
  static const transactionDialogWidth = 560.0;
  static const transactionFieldHeight = 64.0;
  static const transactionFormGap = 12.0;
  static const draftWarningColor = Color(0xFFFFBE66);
  static const draftSegmentMinWidth = 320.0;
  static const draftWarningBorderWidth = 1.5;
  static const quickInputWidth = 720.0;
  static const quickInputStackBreakpoint = 500.0;
  static const quickInputPulseDuration = Duration(milliseconds: 800);
  static const transactionIconSize = 30.0;
  static const _blue = Color(0xFF5B8CFF);
  static const _surface = Color(0xFF071426);
  static const _glass = Color(0x1FFFFFFF);

  /// Shared by page headers, AppBars, and the transaction form title.
  static TextStyle pageTitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.appBarTheme.titleTextStyle ??
        theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w700);
  }

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _blue,
        brightness: Brightness.dark,
        surface: _surface,
      ),
    );
    final scheme = base.colorScheme;
    final textTheme = base.textTheme.apply(
      fontFamily: 'Manrope',
      bodyColor: const Color(0xFFF3F7FF),
      displayColor: const Color(0xFFF8FAFF),
    );
    final pageTitle = textTheme.headlineSmall!.copyWith(
      fontSize: pageTitleFontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.33,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        titleTextStyle: pageTitle,
        toolbarHeight: toolbarHeight,
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFFF3F7FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: _glass,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: .14)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: .18),
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .055),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: TextStyle(color: scheme.primary.withValues(alpha: .9)),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        hintStyle: const TextStyle(color: Color(0xFFB8C4D8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3564C9),
          foregroundColor: const Color(0xFFFFFFFF),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: const Color(0xFFE6EEFF),
          side: BorderSide(color: Colors.white.withValues(alpha: .26)),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xD9091930),
        indicatorColor: _blue.withValues(alpha: .32),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xA6091930),
        indicatorColor: _blue.withValues(alpha: .28),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(
          color: Colors.white.withValues(alpha: .54),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xEE0A1A32),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.white.withValues(alpha: .18)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xF20A1A32),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
