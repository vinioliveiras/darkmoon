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
  /// **'Open File'**
  String get menuOpenFile;

  /// No description provided for @menuOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get menuOpenFolder;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @dialogOpenFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
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

  /// No description provided for @loadingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Loading photos... ({loaded}/{total})'**
  String loadingPhotos(int loaded, int total);

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

  /// No description provided for @sidebarRecentFilesSection.
  ///
  /// In en, this message translates to:
  /// **'RECENT FILES'**
  String get sidebarRecentFilesSection;

  /// No description provided for @sidebarFoldersSection.
  ///
  /// In en, this message translates to:
  /// **'FOLDERS'**
  String get sidebarFoldersSection;

  /// No description provided for @sidebarRemoveFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove folder'**
  String get sidebarRemoveFolderTooltip;

  /// No description provided for @sidebarPresetsSection.
  ///
  /// In en, this message translates to:
  /// **'PRESETS'**
  String get sidebarPresetsSection;

  /// No description provided for @presetImportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import presets (.xmp or .zip)'**
  String get presetImportTooltip;

  /// No description provided for @presetSaveNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save current edits as a preset'**
  String get presetSaveNewTooltip;

  /// No description provided for @presetEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No presets yet'**
  String get presetEmptyHint;

  /// No description provided for @presetRenameLabel.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get presetRenameLabel;

  /// No description provided for @presetExportLabel.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get presetExportLabel;

  /// No description provided for @presetDeleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get presetDeleteLabel;

  /// No description provided for @presetSaveLabel.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get presetSaveLabel;

  /// No description provided for @presetSaveNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Save preset'**
  String get presetSaveNewTitle;

  /// No description provided for @presetRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename preset'**
  String get presetRenameTitle;

  /// No description provided for @presetExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export preset'**
  String get presetExportDialogTitle;

  /// No description provided for @presetImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import presets'**
  String get presetImportDialogTitle;

  /// No description provided for @presetDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete the preset \"{name}\"? This can\'t be undone.'**
  String presetDeleteConfirmMessage(String name);

  /// No description provided for @presetDeleteManyConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} presets? This can\'t be undone.'**
  String presetDeleteManyConfirmMessage(int count);

  /// No description provided for @presetSelectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select presets'**
  String get presetSelectTooltip;

  /// No description provided for @presetSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String presetSelectedCount(int count);

  /// No description provided for @presetUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'Some settings weren\'t applied'**
  String get presetUnsupportedTitle;

  /// No description provided for @presetUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'The preset \"{name}\" has settings this app doesn\'t support yet, so they were skipped:'**
  String presetUnsupportedMessage(String name);

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
  /// **'Before/After'**
  String get beforeAfterButton;

  /// No description provided for @fullQualityButton.
  ///
  /// In en, this message translates to:
  /// **'Full Quality'**
  String get fullQualityButton;

  /// No description provided for @fullQualityShortLabel.
  ///
  /// In en, this message translates to:
  /// **'HD'**
  String get fullQualityShortLabel;

  /// No description provided for @exportPanelButton.
  ///
  /// In en, this message translates to:
  /// **'Export'**
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

  /// No description provided for @settingsUserDataSection.
  ///
  /// In en, this message translates to:
  /// **'USER DATA'**
  String get settingsUserDataSection;

  /// No description provided for @settingsClearThumbnailsButton.
  ///
  /// In en, this message translates to:
  /// **'Clear thumbnail cache'**
  String get settingsClearThumbnailsButton;

  /// No description provided for @settingsClearRecentFilesButton.
  ///
  /// In en, this message translates to:
  /// **'Clear recent files list'**
  String get settingsClearRecentFilesButton;

  /// No description provided for @settingsClearCatalogButton.
  ///
  /// In en, this message translates to:
  /// **'Clear catalog (all edits)'**
  String get settingsClearCatalogButton;

  /// No description provided for @confirmClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear data?'**
  String get confirmClearTitle;

  /// No description provided for @confirmClearThumbnailsMessage.
  ///
  /// In en, this message translates to:
  /// **'This deletes every cached thumbnail. They\'ll be regenerated next time you open a folder.'**
  String get confirmClearThumbnailsMessage;

  /// No description provided for @confirmClearRecentFilesMessage.
  ///
  /// In en, this message translates to:
  /// **'This clears your recent files list. Folders you\'ve added stay untouched.'**
  String get confirmClearRecentFilesMessage;

  /// No description provided for @confirmClearCatalogMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes every saved edit for every photo. This can\'t be undone.'**
  String get confirmClearCatalogMessage;

  /// No description provided for @clearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearButton;

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

  /// No description provided for @sectionDetail.
  ///
  /// In en, this message translates to:
  /// **'DETAIL'**
  String get sectionDetail;

  /// No description provided for @sectionToneCurve.
  ///
  /// In en, this message translates to:
  /// **'TONE CURVE'**
  String get sectionToneCurve;

  /// No description provided for @sectionColorCurve.
  ///
  /// In en, this message translates to:
  /// **'COLOR CURVE'**
  String get sectionColorCurve;

  /// No description provided for @sectionColorMixer.
  ///
  /// In en, this message translates to:
  /// **'COLOR MIXER'**
  String get sectionColorMixer;

  /// No description provided for @sectionColorGrading.
  ///
  /// In en, this message translates to:
  /// **'COLOR GRADING'**
  String get sectionColorGrading;

  /// No description provided for @gradeRangeMidtones.
  ///
  /// In en, this message translates to:
  /// **'Midtones'**
  String get gradeRangeMidtones;

  /// No description provided for @maskImageLayer.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get maskImageLayer;

  /// No description provided for @maskLinearGradient.
  ///
  /// In en, this message translates to:
  /// **'Linear Gradient'**
  String get maskLinearGradient;

  /// No description provided for @maskRadialGradient.
  ///
  /// In en, this message translates to:
  /// **'Radial Gradient'**
  String get maskRadialGradient;

  /// No description provided for @maskBrush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get maskBrush;

  /// No description provided for @maskAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add mask'**
  String get maskAddTooltip;

  /// No description provided for @maskEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get maskEnabledLabel;

  /// No description provided for @maskInvertLabel.
  ///
  /// In en, this message translates to:
  /// **'Invert'**
  String get maskInvertLabel;

  /// No description provided for @maskDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete mask'**
  String get maskDeleteTooltip;

  /// No description provided for @maskBrushSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get maskBrushSizeLabel;

  /// No description provided for @maskBrushHardnessLabel.
  ///
  /// In en, this message translates to:
  /// **'Hardness'**
  String get maskBrushHardnessLabel;

  /// No description provided for @maskBrushEraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Erase'**
  String get maskBrushEraseLabel;

  /// No description provided for @maskUndoStrokeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Undo last stroke'**
  String get maskUndoStrokeTooltip;

  /// No description provided for @maskColorRange.
  ///
  /// In en, this message translates to:
  /// **'Color Range'**
  String get maskColorRange;

  /// No description provided for @colorRangeToleranceLabel.
  ///
  /// In en, this message translates to:
  /// **'Tolerance'**
  String get colorRangeToleranceLabel;

  /// No description provided for @colorRangeFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get colorRangeFeatherLabel;

  /// No description provided for @colorRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the image to pick a color'**
  String get colorRangeHint;

  /// No description provided for @colorChannelRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorChannelRed;

  /// No description provided for @colorChannelOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorChannelOrange;

  /// No description provided for @colorChannelYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorChannelYellow;

  /// No description provided for @colorChannelGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorChannelGreen;

  /// No description provided for @colorChannelAqua.
  ///
  /// In en, this message translates to:
  /// **'Aqua'**
  String get colorChannelAqua;

  /// No description provided for @colorChannelBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorChannelBlue;

  /// No description provided for @colorChannelPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorChannelPurple;

  /// No description provided for @colorChannelMagenta.
  ///
  /// In en, this message translates to:
  /// **'Magenta'**
  String get colorChannelMagenta;

  /// No description provided for @mixerHueLabel.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get mixerHueLabel;

  /// No description provided for @mixerSaturationLabel.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get mixerSaturationLabel;

  /// No description provided for @mixerLuminanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Luminance'**
  String get mixerLuminanceLabel;

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

  /// No description provided for @sliderDenoiseLuminance.
  ///
  /// In en, this message translates to:
  /// **'Luminance'**
  String get sliderDenoiseLuminance;

  /// No description provided for @sliderDenoiseLuminanceDetail.
  ///
  /// In en, this message translates to:
  /// **'Luminance Detail'**
  String get sliderDenoiseLuminanceDetail;

  /// No description provided for @sliderDenoiseLuminanceContrast.
  ///
  /// In en, this message translates to:
  /// **'Luminance Contrast'**
  String get sliderDenoiseLuminanceContrast;

  /// No description provided for @sliderDenoiseColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get sliderDenoiseColor;

  /// No description provided for @sliderDenoiseColorDetail.
  ///
  /// In en, this message translates to:
  /// **'Color Detail'**
  String get sliderDenoiseColorDetail;

  /// No description provided for @sliderDenoiseColorSmoothness.
  ///
  /// In en, this message translates to:
  /// **'Color Smoothness'**
  String get sliderDenoiseColorSmoothness;
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
