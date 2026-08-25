import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Displayed app version — bump this alongside the git tag on each release
/// (pubspec.yaml's own version is frozen at 1.0.0+1 and isn't the
/// user-facing version; releases are tracked purely via git tags, see
/// README/release notes).
const String darkmoonAppVersion = 'v0.9.3';

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
            Text(
              'Darkmoon',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: DarkmoonColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              darkmoonAppVersion,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: DarkmoonColors.textMuted),
            ),
            const SizedBox(height: 16),
            Text(l10n.aboutCredits),
            const SizedBox(height: 4),
            const SelectableText(
              'github.com/vinioliveiras',
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
