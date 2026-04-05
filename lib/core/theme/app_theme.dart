import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
  // ── Pre-computed alpha variants (avoid .withValues in build) ────
  static const Color gold85 = Color(0xD9D4A84B); // gold @ 0.85
  static const Color gold60 = Color(0x99D4A84B); // gold @ 0.60
  static const Color gold40 = Color(0x66D4A84B); // gold @ 0.40
  static const Color gold35 = Color(0x59D4A84B); // gold @ 0.35
  static const Color gold25 = Color(0x40D4A84B); // gold @ 0.25
  static const Color gold15 = Color(0x26D4A84B); // gold @ 0.15
  static const Color gold12 = Color(0x1FD4A84B); // gold @ 0.12
  static const Color gold10 = Color(0x1AD4A84B); // gold @ 0.10
  static const Color gold08 = Color(0x14D4A84B); // gold @ 0.08
  static const Color gold06 = Color(0x0FD4A84B); // gold @ 0.06
  static const Color gold04 = Color(0x0AD4A84B); // gold @ 0.04
  static const Color gold03 = Color(0x08D4A84B); // gold @ 0.03
  static const Color gold20 = Color(0x33D4A84B); // gold @ 0.20
  static const Color gold18 = Color(0x2ED4A84B); // gold @ 0.18
  static const Color gold14 = Color(0x24D4A84B); // gold @ 0.14
  static const Color gold65 = Color(0xA6D4A84B); // gold @ 0.65
  static const Color gold30 = Color(0x4DD4A84B); // gold @ 0.30

  static const Color textMuted80 = Color(0xCC5A6A7E); // textMuted @ 0.80
  static const Color textMuted60 = Color(0x995A6A7E); // textMuted @ 0.60
  static const Color textMuted50 = Color(0x805A6A7E); // textMuted @ 0.50
  static const Color textMuted40 = Color(0x665A6A7E); // textMuted @ 0.40
  static const Color textMuted30 = Color(0x4D5A6A7E); // textMuted @ 0.30
  static const Color textMuted08 = Color(0x145A6A7E); // textMuted @ 0.08

  static const Color surfaceAlpha85 = Color(0xD90E1620); // surface @ 0.85
  static const Color surfaceAlpha45 = Color(0x730E1620); // surface @ 0.45
  static const Color surfaceLightAlpha60 = Color(0x9915202E); // surfaceLight @ 0.60
  static const Color surfaceLightAlpha55 = Color(0x8C15202E); // surfaceLight @ 0.55
  static const Color dividerAlpha60 = Color(0x991C2A3A); // divider @ 0.60
  static const Color dividerAlpha50 = Color(0x801C2A3A); // divider @ 0.50
  static const Color errorAlpha10 = Color(0x1AE5503E); // error @ 0.10
  static const Color textSecondaryAlpha80 = Color(0xCC9EACBD); // textSecondary @ 0.80
  static const Color bgTransparent = Color(0x00060B11); // background @ 0.0
  static const Color black32 = Color(0x52000000); // black @ 0.32
  static const Color black28 = Color(0x47000000); // black @ 0.28
  static const Color black18 = Color(0x2E000000); // black @ 0.18
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

  /// Fade-out gradient used at the bottom of scrollable areas.
  static const LinearGradient footerFadeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTransparent, background],
    stops: [0.0, 0.3],
  );

  /// Shared nav-bar decoration (glass).
  static const BoxDecoration navBarDecoration = BoxDecoration(
    color: surfaceAlpha85,
    border: Border(
      top: BorderSide(color: dividerAlpha60, width: 0.5),
    ),
  );
}

class AppTheme {
  AppTheme._();

  /// Shared MarkdownStyleSheet for answer/response views.
  static final MarkdownStyleSheet markdownStyle = MarkdownStyleSheet(
    p: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
      height: 1.65,
    ),
    strong: const TextStyle(
      color: AppColors.gold,
      fontWeight: FontWeight.w700,
    ),
    h1: const TextStyle(
      color: AppColors.gold,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
    h2: const TextStyle(
      color: AppColors.gold,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    ),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: AppColors.gold, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    codeblockDecoration: BoxDecoration(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(10),
    ),
  );

  /// Compact MarkdownStyleSheet for inline previews (smaller font).
  static final MarkdownStyleSheet markdownCompactStyle = MarkdownStyleSheet(
    p: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 13,
      height: 1.5,
    ),
    strong: const TextStyle(
      color: AppColors.gold,
      fontWeight: FontWeight.bold,
    ),
  );

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
