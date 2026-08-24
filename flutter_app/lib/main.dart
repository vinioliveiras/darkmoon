import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_screen.dart';
import 'l10n/app_localizations.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/splash_screen.dart';

void main() {
  runApp(const DarkmoonApp());
}

/// Talks to `FlutterWindow`'s method-call handler in windows/runner/
/// flutter_window.cpp — the window starts small and centered (see
/// windows/runner/main.cpp) so the real desktop is visible around the
/// splash card like Lightroom's own launch screen, and this is what grows
/// it to maximized once the splash goes away. Windows-only: the window
/// choreography this exists for is specific to how windows/runner/main.cpp
/// creates the window, so this channel has no handler (and isn't called)
/// on any other platform.
const _windowChannel = MethodChannel('darkmoon/window');

Future<void> _maximizeNativeWindow() async {
  if (!Platform.isWindows) {
    return;
  }
  try {
    await _windowChannel.invokeMethod<void>('maximize');
  } on PlatformException {
    // Best-effort — worst case the window just stays at its small,
    // splash-sized dimensions instead of growing to fill the screen.
  }
}

/// Minimum time the splash screen stays up, regardless of how fast
/// [EditorScreen]'s own startup work (settings/catalog/cache loads, opening
/// the last-active folder) finishes underneath it — long enough to read the
/// branding without it just flashing by, and — more importantly — to give
/// `_preloadPreviewCache`'s background RAW decodes (see editor_screen.dart)
/// a real window to actually finish in, not just skip straight to whatever
/// was already cached from a previous run. EditorScreen mounts (and starts
/// loading) immediately, in parallel with this timer, rather than waiting
/// for it.
const Duration _splashMinDuration = Duration(milliseconds: 4000);

Locale? localeForLanguage(String language) {
  switch (language) {
    case 'en':
      return const Locale('en');
    case 'pt':
      return const Locale('pt');
    default:
      // 'auto' — null tells MaterialApp to resolve from the system locale
      // against supportedLocales itself.
      return null;
  }
}

class DarkmoonApp extends StatefulWidget {
  const DarkmoonApp({super.key});

  @override
  State<DarkmoonApp> createState() => _DarkmoonAppState();
}

class _DarkmoonAppState extends State<DarkmoonApp> {
  Locale? _locale;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLanguage());
    unawaited(
      Future.delayed(_splashMinDuration, () async {
        await _maximizeNativeWindow();
        if (mounted) {
          setState(() => _showSplash = false);
        }
      }),
    );
  }

  Future<void> _loadLanguage() async {
    final settings = await loadSettings();
    if (!mounted) {
      return;
    }
    setState(() => _locale = localeForLanguage(settings.language));
  }

  /// Applies a language change immediately (no restart needed), called
  /// from the Settings dialog via EditorScreen.
  void _onLanguageChanged(String language) {
    setState(() => _locale = localeForLanguage(language));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darkmoon',
      debugShowCheckedModeBanner: false,
      theme: buildDarkmoonTheme(),
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Stack(
        children: [
          // Mounted immediately (not lazily, once the splash goes away) so
          // its initState kicks off settings/catalog/cache loading and
          // reopening the last-active folder in parallel with the splash's
          // fixed timer above, rather than only starting once the splash
          // finishes.
          EditorScreen(onLanguageChanged: _onLanguageChanged),
          IgnorePointer(
            ignoring: !_showSplash,
            child: AnimatedOpacity(
              opacity: _showSplash ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: const SplashScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
