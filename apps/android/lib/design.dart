import 'package:flutter/material.dart';

// Persisted user rules: docs/DESIGN.md. Use these tokens in future updates.
const accent = Color(0xFF77E2C2);
const panel = Color(0xFF172526);
const appBackground = Color(0xFF101B1C);
const inputSurface = Color(0xFF1C2C2D);
const textPrimary = Color(0xFFF2F7F5);
const textSecondary = Color(0xFFB8C9C6);
const onAccent = Color(0xFF09221B);

ThemeData buildAppTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  TextStyle regular(TextStyle? style) => (style ?? const TextStyle()).copyWith(
    color: textPrimary,
    fontWeight: FontWeight.w400,
  );
  TextStyle strong(TextStyle? style) => regular(
    style,
  ).copyWith(fontWeight: FontWeight.w600, fontFamily: 'Roboto');
  final text = base.textTheme;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  return base.copyWith(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          onPrimary: onAccent,
          surface: appBackground,
          onSurface: textPrimary,
          onSurfaceVariant: textSecondary,
          error: const Color(0xFFFFBCAD),
          onError: onAccent,
        ),
    scaffoldBackgroundColor: appBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: appBackground,
      foregroundColor: textPrimary,
      toolbarHeight: 72,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: text.copyWith(
      displayLarge: strong(text.displayLarge),
      displayMedium: strong(text.displayMedium),
      displaySmall: strong(text.displaySmall),
      headlineLarge: strong(text.headlineLarge),
      headlineMedium: strong(text.headlineMedium),
      headlineSmall: strong(text.headlineSmall),
      titleLarge: strong(text.titleLarge),
      titleMedium: strong(text.titleMedium),
      titleSmall: strong(text.titleSmall),
      bodyLarge: regular(text.bodyLarge),
      bodyMedium: regular(text.bodyMedium),
      bodySmall: regular(text.bodySmall),
      labelLarge: strong(text.labelLarge),
      labelMedium: strong(text.labelMedium),
      labelSmall: strong(text.labelSmall),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputSurface,
      contentPadding: const EdgeInsets.all(16),
      labelStyle: const TextStyle(
        color: textSecondary,
        fontWeight: FontWeight.w400,
      ),
      helperStyle: const TextStyle(
        color: textSecondary,
        fontWeight: FontWeight.w400,
      ),
      hintStyle: const TextStyle(
        color: textSecondary,
        fontWeight: FontWeight.w400,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        backgroundColor: accent,
        foregroundColor: onAccent,
        shape: buttonShape,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        foregroundColor: textPrimary,
        shape: buttonShape,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(8),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      backgroundColor: inputSurface,
      padding: const EdgeInsets.all(8),
      labelStyle: const TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
    ),
    dividerTheme: const DividerThemeData(color: inputSurface, thickness: 1),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: textSecondary,
      textColor: textPrimary,
      collapsedTextColor: textPrimary,
      collapsedIconColor: textSecondary,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 80,
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: inputSurface,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
