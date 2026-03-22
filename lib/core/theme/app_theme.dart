import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // ── Core palette ───────────────────────────────────────────────────
  static const Color background = Color(0xFF060B11);
  static const Color surface = Color(0xFF0E1620);
  static const Color surfaceLight = Color(0xFF15202E);
  static const Color card = Color(0xFF121D2B);
  static const Color cardHighlight = Color(0xFF182638);

  // ── Accent ─────────────────────────────────────────────────────────
  static const Color gold = Color(0xFFD4A84B);
  static const Color goldLight = Color(0xFFEDD48B);
  static const Color goldDark = Color(0xFFAD8528);
  static const Color accent = Color(0xFF3ECFA5); // teal highlight

  // ── Text ───────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F2F5);
  static const Color textSecondary = Color(0xFF9EACBD);
  static const Color textMuted = Color(0xFF5A6A7E);

  // ── Semantic ───────────────────────────────────────────────────────
  static const Color error = Color(0xFFE5503E);
  static const Color success = Color(0xFF3ECFA5);
  static const Color divider = Color(0xFF1C2A3A);
  static const Color shimmer = Color(0xFF1C2A3A);

  // ── Helpers ────────────────────────────────────────────────────────
  static LinearGradient get cardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [card, Color(0xFF0F1A26)],
      );

  static LinearGradient get goldGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [goldDark, gold, goldLight],
        stops: [0.0, 0.45, 1.0],
      );

  static LinearGradient get surfaceGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [surface, background],
      );
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.gold,
        brightness: Brightness.dark,
        surface: AppColors.surface,
        primary: AppColors.gold,
        onPrimary: AppColors.background,
        secondary: AppColors.accent,
        error: AppColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: AppColors.gold, size: 22),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.gold,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.plusJakartaSans(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.8,
        ),
        headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
        bodySmall: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: AppColors.textMuted,
          height: 1.3,
        ),
        labelLarge: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.gold,
          letterSpacing: 0.6,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.background,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.5), width: 1.5),
        ),
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
      iconTheme: const IconThemeData(color: AppColors.gold, size: 22),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimary,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
