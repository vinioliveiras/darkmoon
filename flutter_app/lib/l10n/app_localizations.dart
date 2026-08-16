import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open File...'**
  String get menuOpenFile;

  /// No description provided for @menuOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder...'**
  String get menuOpenFolder;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings...'**
  String get menuSettings;

  /// No description provided for @dialogOpenFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get dialogOpenFolderTitle;

  /// No description provided for @dialogOpenFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Open RAW File'**
  String get dialogOpenFileTitle;

  /// No description provided for @loadingFolder.
  ///
  /// In en, this message translates to:
  /// **'Loading folder...'**
  String get loadingFolder;

  /// No description provided for @loadingImage.
  ///
  /// In en, this message translates to:
  /// **'Loading {name}...'**
  String loadingImage(String name);

  /// No description provided for @applyingAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Applying adjustments...'**
  String get applyingAdjustments;

  /// No description provided for @emptyStateOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open a folder with RAW files to get started'**
  String get emptyStateOpenFolder;

  /// No description provided for @noFolderOpen.
  ///
  /// In en, this message translates to:
  /// **'No folder open'**
  String get noFolderOpen;

  /// No description provided for @decodingPhoto.
  ///
  /// In en, this message translates to:
  /// **'{name}\n(decoding...)'**
  String decodingPhoto(String name);

  /// No description provided for @beforeLabel.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get beforeLabel;

  /// No description provided for @afterLabel.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get afterLabel;

  /// No description provided for @zoomFit.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get zoomFit;

  /// No description provided for @fitToWindow.
  ///
  /// In en, this message translates to:
  /// **'Fit to window'**
  String get fitToWindow;

  /// No description provided for @beforeAfterButton.
  ///
  /// In en, this message translates to:
  /// **'Before/After (\\)'**
  String get beforeAfterButton;

  /// No description provided for @fullQualityButton.
  ///
  /// In en, this message translates to:
  /// **'Full Quality'**
  String get fullQualityButton;

  /// No description provided for @exportPanelButton.
  ///
  /// In en, this message translates to:
  /// **'Export...'**
  String get exportPanelButton;

  /// No description provided for @exportingButton.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get exportingButton;

  /// No description provided for @exportPhotoDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Photo'**
  String get exportPhotoDialogTitle;

  /// No description provided for @exportFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get exportFormatLabel;

  /// No description provided for @exportQualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get exportQualityLabel;

  /// No description provided for @exportDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportDialogConfirm;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @exportSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportSuccessMessage(String path);

  /// No description provided for @exportFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailureMessage(String error);

  /// No description provided for @resetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset adjustments'**
  String get resetTooltip;

  /// No description provided for @settingsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsDialogTitle;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsLanguageAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (system)'**
  String get settingsLanguageAuto;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get settingsLanguagePortuguese;

  /// No description provided for @settingsFastPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Fast preview while dragging sliders'**
  String get settingsFastPreviewLabel;

  /// No description provided for @settingsAlwaysFullQualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Always open photos in full quality'**
  String get settingsAlwaysFullQualityLabel;

  /// No description provided for @settingsThumbnailThreadsLabel.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail loading threads'**
  String get settingsThumbnailThreadsLabel;

  /// No description provided for @closeButton.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButton;

  /// No description provided for @sectionWhiteBalance.
  ///
  /// In en, this message translates to:
  /// **'WHITE BALANCE'**
  String get sectionWhiteBalance;

  /// No description provided for @sectionTone.
  ///
  /// In en, this message translates to:
  /// **'TONE'**
  String get sectionTone;

  /// No description provided for @sectionPresence.
  ///
  /// In en, this message translates to:
  /// **'PRESENCE'**
  String get sectionPresence;

  /// No description provided for @sliderTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get sliderTemperature;

  /// No description provided for @sliderTint.
  ///
  /// In en, this message translates to:
  /// **'Tint'**
  String get sliderTint;

  /// No description provided for @sliderExposure.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get sliderExposure;

  /// No description provided for @sliderBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get sliderBrightness;

  /// No description provided for @sliderContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get sliderContrast;

  /// No description provided for @sliderHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get sliderHighlights;

  /// No description provided for @sliderShadows.
  ///
  /// In en, this message translates to:
  /// **'Shadows'**
  String get sliderShadows;

  /// No description provided for @sliderWhites.
  ///
  /// In en, this message translates to:
  /// **'Whites'**
  String get sliderWhites;

  /// No description provided for @sliderBlacks.
  ///
  /// In en, this message translates to:
  /// **'Blacks'**
  String get sliderBlacks;

  /// No description provided for @sliderTexture.
  ///
  /// In en, this message translates to:
  /// **'Texture'**
  String get sliderTexture;

  /// No description provided for @sliderClarity.
  ///
  /// In en, this message translates to:
  /// **'Clarity'**
  String get sliderClarity;

  /// No description provided for @sliderDehaze.
  ///
  /// In en, this message translates to:
  /// **'Dehaze'**
  String get sliderDehaze;

  /// No description provided for @sliderVibrance.
  ///
  /// In en, this message translates to:
  /// **'Vibrance'**
  String get sliderVibrance;

  /// No description provided for @sliderSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get sliderSaturation;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
