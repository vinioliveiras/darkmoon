import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'about_dialog.dart' show darkmoonAppVersion;

/// Lightroom-style launch screen — shown for a fixed minimum duration (see
/// `main.dart`'s `_splashMinDuration`) while [EditorScreen] loads
/// underneath (settings, catalog, thumbnail/preview caches, the
/// last-active folder), so that work gets a head start before the editor
/// is actually revealed instead of the user watching it happen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: DarkmoonColors.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed featured photo, darkened so the centered branding
          // stays legible over any part of it — same "photo behind glass"
          // treatment Lightroom's own splash uses.
          Positioned.fill(
            child: Image.asset('assets/splash/featured.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/splash/app_icon.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Darkmoon',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  darkmoonAppVersion,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Column(
              children: [
                Text(
                  l10n.aboutCredits,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.splashLicense,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
