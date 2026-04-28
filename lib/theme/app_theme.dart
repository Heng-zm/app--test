import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Color Palette (Deep Cyberpunk) ────────────────────────────────────────
  static const Color bgDeep = Color(0xFF070B14);
  static const Color bgCard = Color(0xFF0D1526);
  static const Color bgSurface = Color(0xFF111D35);

  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentTeal = Color(0xFF00BFA5);
  static const Color accentPurple = Color(0xFF7C4DFF);
  static const Color accentGreen = Color(0xFF00E676);

  static const Color textPrimary = Color(0xFFE8F4F8);
  static const Color textSecondary = Color(0xFF7A9BB5);
  static const Color textDim = Color(0xFF3D5A73);

  static const Color danger = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFD740);

  static const Color myBubble = Color(0xFF0A3D62);
  static const Color theirBubble = Color(0xFF0D1E33);
  static const Color borderGlow = Color(0xFF1A4A6B);

  // 🟢 PERF: Cached Text Styles to avoid repeated GoogleFonts lookups
  static final TextStyle _monoBase = GoogleFonts.spaceMono(color: textPrimary);
  static final TextStyle _interBase = GoogleFonts.inter(color: textPrimary);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,
      canvasColor: bgSurface,
      primaryColor: accentCyan,

      // 🟢 FIX: Themed text selection to match the Cyan aesthetic
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accentCyan,
        selectionColor: Color(0x4D00E5FF),
        selectionHandleColor: accentCyan,
      ),

      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        onPrimary: bgDeep,
        secondary: accentTeal,
        surface: bgCard,
        onSurface: textPrimary,
        error: danger,
      ),

      // ── Typography ────────────────────────────────────────────────────────
      textTheme: TextTheme(
        displayLarge: _monoBase.copyWith(
            fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1),
        displayMedium:
            _monoBase.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
        titleLarge: _monoBase.copyWith(
            fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        titleMedium:
            _interBase.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: _interBase.copyWith(fontSize: 15),
        bodyMedium: _interBase.copyWith(color: textSecondary, fontSize: 13),
        labelSmall: _monoBase.copyWith(
            color: textDim, fontSize: 10, letterSpacing: 1.2),
      ),

      // ── Component Themes ──────────────────────────────────────────────────

      appBarTheme: AppBarTheme(
        backgroundColor: bgDeep,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _monoBase.copyWith(
            fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
        iconTheme: const IconThemeData(color: accentCyan),
      ),

      // 🟢 FIX: Divider theme ensures consistent borders across the Terminal UI
      dividerTheme: const DividerThemeData(
        color: borderGlow,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgSurface,
        contentTextStyle: _interBase.copyWith(fontSize: 14),
        actionTextColor: accentCyan,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: borderGlow),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgSurface,
        indicatorColor: accentCyan.withValues(alpha: 0.1),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected))
            return const IconThemeData(color: accentCyan);
          return const IconThemeData(color: textDim);
        }),
        labelTextStyle: WidgetStateProperty.all(
            _monoBase.copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bgSurface,
        indicatorColor: accentCyan.withValues(alpha: 0.1),
        selectedIconTheme: const IconThemeData(color: accentCyan),
        unselectedIconTheme: const IconThemeData(color: textDim),
        selectedLabelTextStyle: _monoBase.copyWith(
            color: accentCyan, fontSize: 11, fontWeight: FontWeight.bold),
        unselectedLabelTextStyle:
            _monoBase.copyWith(color: textDim, fontSize: 11),
      ),

      cardTheme: CardTheme(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderGlow, width: 1),
        ),
      ),

      dialogTheme: DialogTheme(
        backgroundColor: bgSurface,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderGlow, width: 1),
        ),
        titleTextStyle: _monoBase.copyWith(
            color: accentCyan, fontSize: 18, fontWeight: FontWeight.bold),
        contentTextStyle:
            _interBase.copyWith(color: textSecondary, fontSize: 14),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderGlow)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderGlow)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accentCyan, width: 1.5)),
        hintStyle: _interBase.copyWith(color: textDim, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentCyan,
          foregroundColor: bgDeep,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: _monoBase.copyWith(
              fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
      ),

      iconTheme: const IconThemeData(color: accentCyan),
    );
  }
}
