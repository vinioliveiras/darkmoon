import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'dialog_chrome.dart';

/// Displayed app version — bump this alongside pubspec.yaml's `version:`
/// and the git tag on each release.
const String darkmoonAppVersion = 'v1.11.0';

/// Tapping the app icon this many times in a row triggers the hidden
/// easter egg (see [_DarkmoonAboutDialogState._onIconTap]) — 5 is the
/// classic "developer options" tap count (Android's own "tap build number
/// 7 times" is the same idea, just a different number).
const _easterEggTapCount = 5;

/// Where the packaging put `THIRD_PARTY_LICENSES.md`: beside the
/// executable on Windows and Linux (see each platform's CMakeLists.txt),
/// in `Contents/Resources` on macOS (tool/bundle_macos_natives.sh).
String thirdPartyLicensesPath() {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final dir = Platform.isMacOS
      ? p.join(p.dirname(exeDir), 'Resources')
      : exeDir;
  return p.join(dir, 'THIRD_PARTY_LICENSES.md');
}

/// The same file in the repository, for a build that does not carry it
/// (a `flutter run` from source, the test runner).
final Uri thirdPartyLicensesUrl = Uri.parse(
  'https://github.com/vinioliveiras/darkmoon/blob/master/THIRD_PARTY_LICENSES.md',
);

/// The "About" entry in the top menu bar — app name/version plus credits.
/// Named [DarkmoonAboutDialog] to avoid colliding with Flutter's own
/// [AboutDialog].
class DarkmoonAboutDialog extends StatefulWidget {
  const DarkmoonAboutDialog({super.key});

  @override
  State<DarkmoonAboutDialog> createState() => _DarkmoonAboutDialogState();
}

class _DarkmoonAboutDialogState extends State<DarkmoonAboutDialog> {
  int _iconTapCount = 0;

  /// Just an outbound link (`url_launcher`, opens in the system browser) —
  /// nothing hosted/embedded/redistributed, the same as the repo link
  /// below, so no different a copyright concern than any other credit
  /// link in this dialog.
  Future<void> _onIconTap() async {
    _iconTapCount++;
    if (_iconTapCount < _easterEggTapCount) {
      return;
    }
    _iconTapCount = 0;
    await launchUrl(
      Uri.parse('https://www.youtube.com/watch?v=SGj-ORoxD8U'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Opens the bundled notices file with whatever the system uses for
  /// Markdown, and falls back to the repository copy when the file is not
  /// there or nothing will open it.
  Future<void> _openThirdPartyLicenses() async {
    final local = File(thirdPartyLicensesPath());
    // Sync on purpose: one stat, and an awaited dart:io call never
    // completes under a widget test's fake async zone.
    if (local.existsSync()) {
      final opened = await launchUrl(
        Uri.file(local.path),
        mode: LaunchMode.externalApplication,
      );
      if (opened) {
        return;
      }
    }
    await launchUrl(
      thirdPartyLicensesUrl,
      mode: LaunchMode.externalApplication,
    );
  }

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
      contentPadding: dialogScrollContentPadding,
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: kScrollbarGutter),
          child: SettingsGroup(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => unawaited(_onIconTap()),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/splash/app_icon.png',
                        width: 40,
                        height: 40,
                      ),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                  // Selectable, not a launchable link — select-and-copy
                  // already gets the user to the repo, and turning this
                  // into a tappable link wasn't asked for.
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
              // The bundled notices for LibRaw, ONNX Runtime, DirectML and
              // the models — several of the models are CC-BY, and the
              // attribution has to be reachable from the application.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('about-third-party-licenses'),
                  onPressed: _openThirdPartyLicenses,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: DarkmoonColors.textSecondary,
                  ),
                  child: Text(l10n.aboutThirdPartyLicenses),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
