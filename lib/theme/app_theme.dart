import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color palette - deep navy/teal cyberpunk
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

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,
      primaryColor: accentCyan,
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        secondary: accentTeal,
        surface: bgCard,
        error: danger,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceMono(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -1,
        ),
        displayMedium: GoogleFonts.spaceMono(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: GoogleFonts.spaceMono(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        titleMedium: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 15,
        ),
        bodyMedium: GoogleFonts.inter(
          color: textSecondary,
          fontSize: 13,
        ),
        labelSmall: GoogleFonts.spaceMono(
          color: textDim,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDeep,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.spaceMono(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
        iconTheme: const IconThemeData(color: accentCyan),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderGlow),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderGlow, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentCyan, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(color: textDim, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentCyan,
          foregroundColor: bgDeep,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.spaceMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: accentCyan),
      dividerColor: borderGlow,
    );
  }
}
