import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:animations/animations.dart';
import 'package:vad_app/widgets/snackbar_service.dart';

class AppTheme {
  static const Color bg = Color(0xFF0a0a0f);
  static const Color surface = Color(0xFF16161f);
  static const Color surfaceLight = Color(0xFF1e1e2a);
  static const Color primary = Color(0xFFE2F824);
  static const Color primaryLight = Color(0xFFEEFA68);
  static const Color textMuted = Color(0xFF6b7280);
  static const Color textWhite = Color(0xFFf9fafb);
  static const Color textPrimary = textWhite;
  static const Color textSecondary = Color(0xFF9ca3af);
  static const Color cardBorder = Color(0x1Affffff);
  static const Color error = Color(0xFFef4444);
  static const Color success = Color(0xFF22c55e);
  static const Color warning = Color(0xFFeab308);

  static void showGlassySnackBar({
    required String title,
    required String message,
    IconData icon = Iconsax.info_circle,
  }) {
    infoSnackBar(message, title: title);
  }

  /// Maps a media-list status string to a semantic colour.
  static Color statusColor(String? status) {
    switch (status) {
      case 'WATCHING':
        return primary;
      case 'COMPLETED':
        return success;
      case 'PLAN_TO_WATCH':
        return warning;
      case 'DROPPED':
        return error;
      case 'PAUSED':
        return textMuted;
      default:
        return Colors.white;
    }
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        surface: bg,
        primary: primary,
        secondary: primaryLight,
        error: error,
        onSurface: textWhite,
        onPrimary: Colors.black,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, letterSpacing: -0.2),
          titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, letterSpacing: -0.1),
          bodyLarge: TextStyle(color: textPrimary, height: 1.4),
          bodyMedium: TextStyle(color: textSecondary, height: 1.4),
          bodySmall: TextStyle(color: textMuted, height: 1.3),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
          ),
          TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
          ),
          TargetPlatform.windows: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
          ),
          TargetPlatform.macOS: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
          ),
          TargetPlatform.linux: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
          ),
        },
      ),
    );
  }

  static Route performantFadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}
