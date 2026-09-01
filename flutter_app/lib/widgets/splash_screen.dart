import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'about_dialog.dart' show darkmoonAppVersion;

/// Card size, matching real Meridian's splash proportions (a small
/// floating panel, not a full-screen takeover) — see the reference
/// screenshot this was built from.
const double _cardWidth = 720;
const double _cardHeight = 420;
const double _photoWidth = 340;

/// Meridian-style launch screen — a small dark card (same palette as the
/// rest of Darkmoon's dialogs, fitting for an app named "Darkmoon" rather
/// than copying Meridian's white one), split into a left text/branding
/// column and a right featured photo. The native window itself starts
/// small and centered (see windows/runner/main.cpp) so the real desktop
/// is visible around it, the same way Meridian's own launch screen
/// works — this widget only fills that small window, not the whole
/// screen. Shown for a fixed minimum duration (see `main.dart`'s
/// `_splashMinDuration`) while [EditorScreen] loads underneath (settings,
/// catalog, thumbnail/preview caches, the last-active folder, and a
/// background preview-cache warm-up), so that work gets a head start
/// before the editor is actually revealed instead of the user watching it
/// happen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      // Matches the card exactly — the native window is only slightly
      // larger than the card itself, so this is just the thin margin
      // between the card's shadow and the window edge, not a full-screen
      // backdrop.
      color: DarkmoonColors.dialogBackground,
      child: Center(
        child: Material(
          color: DarkmoonColors.dialogBackground,
          elevation: 24,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: _cardWidth,
            height: _cardHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _cardWidth - _photoWidth,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/splash/app_icon.png',
                                width: 44,
                                height: 44,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'darkmoon',
                              style: TextStyle(
                                color: DarkmoonColors.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.splashCopyright,
                          style: const TextStyle(
                            color: DarkmoonColors.textMuted,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.splashLoading,
                          style: const TextStyle(
                            color: DarkmoonColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          darkmoonAppVersion,
                          style: const TextStyle(
                            color: DarkmoonColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Wrap, not Row: the card's fixed width leaves this
                        // column ~328px wide, and pt-BR's longer
                        // "Desenvolvido por Vini · github.com/..." doesn't
                        // fit on one line at this font size — Wrap drops
                        // the github handle to its own line instead of
                        // overflowing the card's edge.
                        Wrap(
                          children: [
                            Text(
                              l10n.aboutCredits,
                              style: const TextStyle(
                                color: DarkmoonColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                            const Text(
                              '  ·  github.com/vinioliveiras',
                              style: TextStyle(
                                color: DarkmoonColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _photoWidth,
                  child: Image.asset(
                    'assets/splash/featured.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
