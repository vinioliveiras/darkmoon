import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'dialog_chrome.dart';

/// Displayed app version — bump this alongside pubspec.yaml's `version:`
/// and the git tag on each release.
const String darkmoonAppVersion = 'v1.3.0';

/// The "About" entry in the top menu bar — app name/version plus credits.
/// Named [DarkmoonAboutDialog] to avoid colliding with Flutter's own
/// [AboutDialog].
class DarkmoonAboutDialog extends StatelessWidget {
  const DarkmoonAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: DialogTitleRow(
        title: l10n.aboutDialogTitle,
        closeTooltip: l10n.closeButton,
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: SettingsGroup(
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: DarkmoonColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        darkmoonAppVersion,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(
                          color: DarkmoonColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.aboutCredits),
                  const SizedBox(height: 4),
                  // Selectable, not a launchable link: the app has no
                  // url_launcher dependency anywhere else, and adding one
                  // for this single label isn't worth the new
                  // native-plugin surface — select-and-copy already gets
                  // the user to the repo.
                  const SelectableText(
                    'github.com/vinioliveiras/darkmoon',
                    style: TextStyle(color: DarkmoonColors.textSecondary),
                  ),
                ],
              ),
              Text(
                l10n.splashLicense,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DarkmoonColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
