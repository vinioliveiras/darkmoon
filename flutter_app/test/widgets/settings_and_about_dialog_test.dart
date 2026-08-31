import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/settings/app_settings.dart';
import 'package:darkmoon/widgets/about_dialog.dart';
import 'package:darkmoon/widgets/settings_dialog.dart';

/// Records `launchUrl` calls instead of actually opening a browser — the
/// standard `url_launcher` testing pattern (swap `UrlLauncherPlatform
/// .instance`), used by the icon-tap easter egg test below.
class _FakeUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  String? launchedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }
}

Widget _wrap(Widget dialog) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SettingsDialog', () {
    testWidgets('renders every tab and its own iOS-style close button '
        '(no bottom Close text button)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsDialog(
            settings: const AppSettings(),
            onChanged: (_) {},
            onClearThumbnails: () {},
            onClearCatalog: () {},
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);

      // Starts on the General tab.
      expect(find.text('Language'), findsOneWidget);

      // The bottom "Close" text action is gone — replaced by the icon
      // button in the title row.
      expect(find.widgetWithText(TextButton, 'Close'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);

      // Switching tabs shows that tab's own content.
      await tester.tap(find.text('Data'));
      await tester.pumpAndSettle();
      expect(find.text('Clear thumbnail cache'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets(
      'the full-preview scale row is hidden while that switch is off — '
      'its label happens to read the same as the plain preview-resolution '
      'dropdown\'s: "Preview resolution"',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsDialog(
              settings: const AppSettings(dynamicFullPreview: false),
              onChanged: (_) {},
              onClearThumbnails: () {},
              onClearCatalog: () {},
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Performance'));
        await tester.pumpAndSettle();
        expect(find.text('Preview resolution'), findsOneWidget);
      },
    );

    testWidgets('the full-preview scale row shows up once that switch is on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SettingsDialog(
            settings: const AppSettings(dynamicFullPreview: true),
            onChanged: (_) {},
            onClearThumbnails: () {},
            onClearCatalog: () {},
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.text('Preview resolution'), findsNWidgets(2));
    });
  });

  group('DarkmoonAboutDialog', () {
    testWidgets('renders the app name, version, and close button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DarkmoonAboutDialog()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('darkmoon'), findsOneWidget);
      expect(find.text(darkmoonAppVersion), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Close'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets(
      'tapping the app icon 5 times opens the easter egg link; 4 taps '
      'does not',
      (tester) async {
        final originalPlatform = UrlLauncherPlatform.instance;
        final fakePlatform = _FakeUrlLauncherPlatform();
        UrlLauncherPlatform.instance = fakePlatform;
        addTearDown(() => UrlLauncherPlatform.instance = originalPlatform);

        await tester.pumpWidget(_wrap(const DarkmoonAboutDialog()));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final icon = find.image(const AssetImage('assets/splash/app_icon.png'));
        for (var i = 0; i < 4; i++) {
          await tester.tap(icon);
        }
        await tester.pumpAndSettle();
        expect(fakePlatform.launchedUrl, isNull);

        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(
          fakePlatform.launchedUrl,
          'https://www.youtube.com/watch?v=SGj-ORoxD8U',
        );
      },
    );
  });
}
