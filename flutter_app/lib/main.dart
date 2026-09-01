import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'diagnostics/dev_log.dart';
import 'diagnostics/native_stderr_redirect.dart';
import 'editor_screen.dart';
import 'l10n/app_localizations.dart';
import 'settings/app_settings.dart';
import 'theme.dart';
import 'widgets/splash_screen.dart';

/// Loads Developer Mode's persisted value before the first frame and wires
/// both of Flutter's global error hooks to `DevLog` — this is the only
/// place uncaught crashes (as opposed to the errors already caught and
/// handled locally elsewhere, like an AI Enhance failure) ever get logged,
/// so it needs to run before anything else can throw. Errors are still
/// forwarded to Flutter's normal handling afterward (the debug console /
/// red screen behavior is unchanged) — this only adds a second listener,
/// it doesn't replace anything.
Future<void> _initDevLog() async {
  final settings = await loadSettings();
  DevLog.setEnabled(settings.devLogging);

  if (settings.devLogging) {
    // Best-effort experiment (see the function's own doc comment for the
    // reasoning and why it's safe even if it captures nothing) — must run
    // before onnxruntime.dll (or any other native library) is ever
    // touched, which only happens later, from a background isolate.
    final dir = await resolveDevLogDir();
    redirectNativeStderrToFileForDevMode(
      p.join(dir.path, 'native-stderr.log'),
    );
  }

  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    DevLog.logError('FlutterError', details.exception, details.stack);
    defaultOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    DevLog.logError('Uncaught', error, stack);
    return false; // Still let Flutter's own default handling occur.
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_initDevLog());
  runApp(const DarkmoonApp());
}

/// Talks to `FlutterWindow`'s method-call handler in windows/runner/
/// flutter_window.cpp — the window starts small, centered, and frameless
/// (see windows/runner/main.cpp and win32_window.cpp's `SetFrameless`) so
/// the real desktop is visible around the splash card with no mismatched
/// native title bar/close button wrapped around it, like Meridian's own
/// launch screen. This is what restores the normal window frame and grows
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
  } on MissingPluginException {
    // No native handler registered for this channel — always true under
    // `flutter test`'s widget-test harness (there's no real Windows
    // runner backing it), and Platform.isWindows above is still true
    // there since it reflects the *host* OS, not "is a real app window
    // running". Same best-effort fallback as the PlatformException case.
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
    case 'de':
      return const Locale('de');
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
      title: 'darkmoon',
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
