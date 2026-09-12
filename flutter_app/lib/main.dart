import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

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
    redirectNativeStderrToFileForDevMode(p.join(dir.path, 'native-stderr.log'));
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _openWindowAsSplashCard();
  unawaited(_initDevLog());
  runApp(const DarkmoonApp());
}

bool get _hasDesktopWindow =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// The launch choreography, all from Dart (2026-09-13, user's request —
/// it used to be Win32 code in windows/runner, which every other platform
/// would have needed its own copy of; the runners are stock now). The
/// window opens *as* the splash card: frameless, card-sized, centred, so
/// the real desktop shows around it like Meridian's own launch screen.
/// [_growWindowToEditor] gives it a normal frame and maximizes it once
/// the splash is over. window_manager does the same on Windows, macOS
/// and Linux; anything that fails here just leaves a normal window.
Future<void> _openWindowAsSplashCard() async {
  if (!_hasDesktopWindow) {
    return;
  }
  try {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      size: const Size(splashCardWidth, splashCardHeight),
      center: true,
      title: 'darkmoon',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      backgroundColor: DarkmoonColors.dialogBackground,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {
    // No window plugin (a test), or a platform that refused: the window
    // simply opens the way the runner made it.
  }
}

/// The second half of [_openWindowAsSplashCard]: the standard title bar
/// and buttons back, then maximized.
Future<void> _growWindowToEditor() async {
  if (!_hasDesktopWindow) {
    return;
  }
  try {
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    await windowManager.maximize();
  } catch (_) {
    // Best effort — worst case the window stays at its splash size, and
    // the user maximizes it. Always the case under `flutter test`, where
    // no plugin backs the call.
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
        await _growWindowToEditor();
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
      // No semantics tree at all (2026-09-12). Whenever a UI Automation
      // client is around — Chrome Remote Desktop's host, the touch
      // keyboard, a screen reader — the Windows engine of this Flutter
      // version dies inside AccessibilityBridge::CreateRemoveReparentedNodes
      // Update a few seconds after the splash (symbolised from the crash
      // dumps with the engine's PDB), reproduced on releases back to
      // v1.14.0. Blocking WM_GETOBJECT in the runner was not enough: the
      // bridge still came up. An empty tree gives it nothing to reparent.
      // The cost is that assistive technology sees a blank window until
      // the engine is fixed; see PENDING.md for the follow-up.
      builder: (context, child) =>
          ExcludeSemantics(child: child ?? const SizedBox.shrink()),
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
