import 'dart:async';

import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'l10n/app_localizations.dart';
import 'settings/app_settings.dart';
import 'theme.dart';

void main() {
  runApp(const DarkmoonApp());
}

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

  @override
  void initState() {
    super.initState();
    unawaited(_loadLanguage());
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
      home: EditorScreen(onLanguageChanged: _onLanguageChanged),
    );
  }
}
