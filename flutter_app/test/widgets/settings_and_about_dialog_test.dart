import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:darkmoon/l10n/app_localizations.dart';
import 'package:darkmoon/settings/app_settings.dart';
import 'package:darkmoon/widgets/about_dialog.dart';
import 'package:darkmoon/widgets/dialog_chrome.dart';
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
            onPruneMissing: () {},
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
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
              onPruneMissing: () {},
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

    testWidgets('the panel layout dropdown reports the chosen value', (
      tester,
    ) async {
      AppSettings? saved;
      await tester.pumpWidget(
        _wrap(
          SettingsDialog(
            settings: const AppSettings(),
            onChanged: (value) => saved = value,
            onClearThumbnails: () {},
            onClearCatalog: () {},
            onPruneMissing: () {},
          ),
        ),
      );
      // The wrapper opens the dialog from a button rather than showing it
      // directly, so nothing exists until it is tapped.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Tabs are the default, so the dropdown must be showing that and the
      // only thing it can be changed to is the flat list.
      expect(find.text(l10n.settingsPanelLayoutTabbed), findsOneWidget);

      await tester.tap(find.text(l10n.settingsPanelLayoutTabbed));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsPanelLayoutFlat).last);
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(
        saved!.tabbedControlsPanel,
        isFalse,
        reason: 'turning the layout off has to reach the saved settings',
      );
    });

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
            onPruneMissing: () {},
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

  /// A scroll view has to hold [kScrollbarGutter] clear on its right so
  /// the desktop scrollbar does not overlay what it scrolls. Charged to
  /// the content, that inset reads as a margin — the card stops short of
  /// the title above it and the dialog looks off-centre, which is how it
  /// was reported. The dialog pays for it out of its own right margin
  /// instead, so these edges have to come back level.
  group('dialog content lines up with its title', () {
    testWidgets('Settings: title, tab bar and cards share both edges', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          SettingsDialog(
            settings: const AppSettings(),
            onChanged: (_) {},
            onClearThumbnails: () {},
            onClearCatalog: () {},
            onPruneMissing: () {},
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final title = tester.getRect(find.byType(DialogTitleRow));
      final tabs = tester.getRect(find.byType(TabBar));
      final card = tester.getRect(find.byType(SettingsGroup).first);

      expect(tabs.right, closeTo(title.right, 0.01));
      expect(card.right, closeTo(title.right, 0.01));
      expect(tabs.left, closeTo(title.left, 0.01));
      expect(card.left, closeTo(title.left, 0.01));
    });

    testWidgets('About: the card shares both edges with the title', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DarkmoonAboutDialog()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final title = tester.getRect(find.byType(DialogTitleRow));
      final card = tester.getRect(find.byType(SettingsGroup));

      expect(card.right, closeTo(title.right, 0.01));
      expect(card.left, closeTo(title.left, 0.01));
    });
  });
}
