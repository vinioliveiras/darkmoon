import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Displayed app version — bump this alongside the git tag on each release
/// (pubspec.yaml's own version is frozen at 1.0.0+1 and isn't the
/// user-facing version; releases are tracked purely via git tags, see
/// README/release notes).
const String darkmoonAppVersion = 'v1.2.0';

/// The "About" entry in the top menu bar — app name/version plus credits.
/// Named [DarkmoonAboutDialog] to avoid colliding with Flutter's own
/// [AboutDialog].
class DarkmoonAboutDialog extends StatelessWidget {
  const DarkmoonAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.surfaceRaised,
      title: Text(l10n.aboutDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/splash/app_icon.png',
                    width: 40,
                    height: 40,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'darkmoon',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: DarkmoonColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      darkmoonAppVersion,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DarkmoonColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.aboutCredits),
            const SizedBox(height: 4),
            // Selectable, not a launchable link: the app has no
            // url_launcher dependency anywhere else, and adding one for
            // this single label isn't worth the new native-plugin surface
            // — select-and-copy already gets the user to the repo.
            const SelectableText(
              'github.com/vinioliveiras/darkmoon',
              style: TextStyle(color: DarkmoonColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.splashLicense,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: DarkmoonColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.closeButton),
        ),
      ],
    );
  }
}
