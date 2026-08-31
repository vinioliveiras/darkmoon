import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
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
    Locale('de'),
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

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// No description provided for @aboutDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'About darkmoon'**
  String get aboutDialogTitle;

  /// No description provided for @aboutCredits.
  ///
  /// In en, this message translates to:
  /// **'Developed by Vini'**
  String get aboutCredits;

  /// No description provided for @splashLicense.
  ///
  /// In en, this message translates to:
  /// **'GNU Affero General Public License v3.0'**
  String get splashLicense;

  /// No description provided for @splashCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Vini. Licensed under GNU AGPL v3.0.'**
  String get splashCopyright;

  /// No description provided for @splashLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your library…'**
  String get splashLoading;

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

  /// No description provided for @photoNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'{name}\ncan\'t be found — it may have been moved, renamed or deleted outside darkmoon'**
  String photoNotFoundMessage(String name);

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

  /// No description provided for @sidebarRemoveRecentFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent files'**
  String get sidebarRemoveRecentFileTooltip;

  /// No description provided for @sidebarFolderNotFoundTooltip.
  ///
  /// In en, this message translates to:
  /// **'Folder not found — remove it from the list'**
  String get sidebarFolderNotFoundTooltip;

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

  /// No description provided for @presetAmountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply \"{name}\"'**
  String presetAmountDialogTitle(String name);

  /// No description provided for @presetAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get presetAmountLabel;

  /// No description provided for @presetAmountApplyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get presetAmountApplyButton;

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

  /// No description provided for @presetExportManyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Export selected as .zip'**
  String get presetExportManyTooltip;

  /// No description provided for @presetExportManyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export presets'**
  String get presetExportManyDialogTitle;

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

  /// No description provided for @presetSelectAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get presetSelectAllTooltip;

  /// No description provided for @presetSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String presetSelectedCount(int count);

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

  /// No description provided for @cropButton.
  ///
  /// In en, this message translates to:
  /// **'Crop & Transform'**
  String get cropButton;

  /// No description provided for @sectionCropTransform.
  ///
  /// In en, this message translates to:
  /// **'CROP & TRANSFORM'**
  String get sectionCropTransform;

  /// No description provided for @cropAspectLabel.
  ///
  /// In en, this message translates to:
  /// **'Aspect'**
  String get cropAspectLabel;

  /// No description provided for @transformStraightenLabel.
  ///
  /// In en, this message translates to:
  /// **'Straighten'**
  String get transformStraightenLabel;

  /// No description provided for @transformVerticalLabel.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get transformVerticalLabel;

  /// No description provided for @transformHorizontalLabel.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get transformHorizontalLabel;

  /// No description provided for @transformAspectLabel.
  ///
  /// In en, this message translates to:
  /// **'Aspect'**
  String get transformAspectLabel;

  /// No description provided for @transformScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get transformScaleLabel;

  /// No description provided for @cropRotateLeftTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90° left'**
  String get cropRotateLeftTooltip;

  /// No description provided for @cropRotateRightTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90° right'**
  String get cropRotateRightTooltip;

  /// No description provided for @cropDoneButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get cropDoneButton;

  /// No description provided for @undoButton.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoButton;

  /// No description provided for @redoButton.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redoButton;

  /// No description provided for @aiDenoiseButton.
  ///
  /// In en, this message translates to:
  /// **'AI Denoise'**
  String get aiDenoiseButton;

  /// No description provided for @aiDenoiseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Denoise'**
  String get aiDenoiseDialogTitle;

  /// No description provided for @aiDenoiseDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Reduce noise automatically, tuned to keep detail sharp.'**
  String get aiDenoiseDialogMessage;

  /// No description provided for @aiDenoiseLevelOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aiDenoiseLevelOff;

  /// No description provided for @aiDenoiseLevelLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get aiDenoiseLevelLight;

  /// No description provided for @aiDenoiseLevelMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get aiDenoiseLevelMedium;

  /// No description provided for @aiDenoiseLevelStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get aiDenoiseLevelStrong;

  /// No description provided for @aiDenoiseApplyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get aiDenoiseApplyButton;

  /// No description provided for @aiDenoiseApplyingMessage.
  ///
  /// In en, this message translates to:
  /// **'Applying AI Denoise...'**
  String get aiDenoiseApplyingMessage;

  /// No description provided for @aiDenoiseDisablingMessage.
  ///
  /// In en, this message translates to:
  /// **'Disabling AI Denoise...'**
  String get aiDenoiseDisablingMessage;

  /// No description provided for @aiDenoiseTabClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get aiDenoiseTabClassic;

  /// No description provided for @aiDenoiseTabEnhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get aiDenoiseTabEnhance;

  /// No description provided for @aiDenoiseTabCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud AI'**
  String get aiDenoiseTabCloud;

  /// No description provided for @aiDenoiseCloudMessage.
  ///
  /// In en, this message translates to:
  /// **'Send this photo to a cloud AI provider you have your own account and API key with. Costs real money per photo and uploads the photo to a third party — the on-device Enhance tab is free and stays on your machine.'**
  String get aiDenoiseCloudMessage;

  /// No description provided for @aiDenoiseCloudProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiDenoiseCloudProviderLabel;

  /// No description provided for @aiDenoiseCloudProviderOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aiDenoiseCloudProviderOff;

  /// No description provided for @aiDenoiseCloudProviderTopaz.
  ///
  /// In en, this message translates to:
  /// **'Topaz Labs (Denoise)'**
  String get aiDenoiseCloudProviderTopaz;

  /// No description provided for @aiDenoiseCloudProviderOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI (gpt-image-1)'**
  String get aiDenoiseCloudProviderOpenAi;

  /// No description provided for @aiDenoiseCloudProviderGemini.
  ///
  /// In en, this message translates to:
  /// **'Google Gemini'**
  String get aiDenoiseCloudProviderGemini;

  /// No description provided for @aiDenoiseCloudTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiDenoiseCloudTokenLabel;

  /// No description provided for @aiDenoiseCloudTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Paste your API key'**
  String get aiDenoiseCloudTokenHint;

  /// No description provided for @aiDenoiseCloudDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Stored only on this device (Windows Credential Manager), sent only to the selected provider. Each apply uploads the full-resolution photo and is billed by your provider account — results are cached so re-opening or exporting the same photo doesn\'t call it again.'**
  String get aiDenoiseCloudDisclosure;

  /// No description provided for @aiDenoiseCloudGenerativeWarning.
  ///
  /// In en, this message translates to:
  /// **'This provider regenerates the image from a prompt rather than running a dedicated denoise model — it may alter fine detail (faces, text, texture), not just remove noise.'**
  String get aiDenoiseCloudGenerativeWarning;

  /// No description provided for @aiDenoiseCloudFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloud AI denoise failed: {error}'**
  String aiDenoiseCloudFailedMessage(String error);

  /// No description provided for @aiDenoiseCloudFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Cloud denoise failed'**
  String get aiDenoiseCloudFailedStatus;

  /// No description provided for @aiDenoiseCloudStartingMessage.
  ///
  /// In en, this message translates to:
  /// **'Starting cloud denoise…'**
  String get aiDenoiseCloudStartingMessage;

  /// No description provided for @aiDenoiseCloudStageUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo…'**
  String get aiDenoiseCloudStageUploading;

  /// No description provided for @aiDenoiseCloudStageProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get aiDenoiseCloudStageProcessing;

  /// No description provided for @aiDenoiseCloudStageDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading result…'**
  String get aiDenoiseCloudStageDownloading;

  /// No description provided for @aiDenoiseCloudStageDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding photo…'**
  String get aiDenoiseCloudStageDecoding;

  /// No description provided for @aiDenoiseEnhanceMessage.
  ///
  /// In en, this message translates to:
  /// **'Denoise, remove film grain, and double the resolution using a neural network — closer to what the shot\'s real detail looked like before noise and compression. Runs noticeably slower than Classic, especially without a compatible GPU.'**
  String get aiDenoiseEnhanceMessage;

  /// No description provided for @aiDenoiseEnhanceDenoiseLabel.
  ///
  /// In en, this message translates to:
  /// **'Denoise'**
  String get aiDenoiseEnhanceDenoiseLabel;

  /// No description provided for @aiDenoiseEnhanceAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get aiDenoiseEnhanceAmountLabel;

  /// No description provided for @aiDenoiseEnhanceUpscaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Upscale 2x'**
  String get aiDenoiseEnhanceUpscaleLabel;

  /// No description provided for @aiDenoiseEnhanceSharpnessLabel.
  ///
  /// In en, this message translates to:
  /// **'Sharpness'**
  String get aiDenoiseEnhanceSharpnessLabel;

  /// No description provided for @aiDenoiseEnhanceSharpnessCaption.
  ///
  /// In en, this message translates to:
  /// **'Blends in a slower, more detail-synthesizing model — any amount above 0% costs ~3.5 minutes per 24MP photo instead of a few seconds, and can slightly alter (not just sharpen) very small text or detail.'**
  String get aiDenoiseEnhanceSharpnessCaption;

  /// No description provided for @aiDenoiseEnhanceRawDenoiseLabel.
  ///
  /// In en, this message translates to:
  /// **'RAW denoise (before demosaic)'**
  String get aiDenoiseEnhanceRawDenoiseLabel;

  /// No description provided for @aiDenoiseEnhanceRawDenoiseUnavailableCaption.
  ///
  /// In en, this message translates to:
  /// **'Only available for standard Bayer RAW files (not X-Trans, Foveon, or non-RAW formats).'**
  String get aiDenoiseEnhanceRawDenoiseUnavailableCaption;

  /// No description provided for @aiDenoiseEnhanceFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'AI Enhance couldn\'t run on this photo. It\'s been turned back off.'**
  String get aiDenoiseEnhanceFailedMessage;

  /// No description provided for @aiDenoiseCustomModelFallbackMessage.
  ///
  /// In en, this message translates to:
  /// **'Your custom denoise model couldn\'t be used ({error}) — used the default model instead.'**
  String aiDenoiseCustomModelFallbackMessage(String error);

  /// No description provided for @aiDenoiseCustomModelFallbackStatus.
  ///
  /// In en, this message translates to:
  /// **'Custom model failed, used default'**
  String get aiDenoiseCustomModelFallbackStatus;

  /// No description provided for @aiDenoiseEnhanceCpuWarning.
  ///
  /// In en, this message translates to:
  /// **'Your GPU doesn\'t support this yet, so it\'s running on the CPU instead — this will take noticeably longer.'**
  String get aiDenoiseEnhanceCpuWarning;

  /// No description provided for @aiDenoiseEnhanceGpuIncompatibleWarning.
  ///
  /// In en, this message translates to:
  /// **'Your GPU isn\'t compatible with this yet, so it\'ll run on the CPU — expect this to take noticeably longer (up to a couple of minutes on a large photo).'**
  String get aiDenoiseEnhanceGpuIncompatibleWarning;

  /// No description provided for @aiDenoiseEnhanceStartingMessage.
  ///
  /// In en, this message translates to:
  /// **'Running AI Enhance...'**
  String get aiDenoiseEnhanceStartingMessage;

  /// No description provided for @aiDenoiseEnhanceStageDenoise.
  ///
  /// In en, this message translates to:
  /// **'Denoising'**
  String get aiDenoiseEnhanceStageDenoise;

  /// No description provided for @aiDenoiseEnhanceStageUpscale.
  ///
  /// In en, this message translates to:
  /// **'Upscaling'**
  String get aiDenoiseEnhanceStageUpscale;

  /// No description provided for @aiDenoiseEnhanceStageRawDenoise.
  ///
  /// In en, this message translates to:
  /// **'Denoising (RAW)'**
  String get aiDenoiseEnhanceStageRawDenoise;

  /// No description provided for @aiDenoiseEnhanceTileProgress.
  ///
  /// In en, this message translates to:
  /// **'{stage} — {percent}%'**
  String aiDenoiseEnhanceTileProgress(String stage, int percent);

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

  /// No description provided for @exportStageDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding RAW...'**
  String get exportStageDecoding;

  /// No description provided for @exportStageRendering.
  ///
  /// In en, this message translates to:
  /// **'Applying edits...'**
  String get exportStageRendering;

  /// No description provided for @exportStageEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding...'**
  String get exportStageEncoding;

  /// No description provided for @exportStageWriting.
  ///
  /// In en, this message translates to:
  /// **'Saving file...'**
  String get exportStageWriting;

  /// No description provided for @exportPhotoDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Photo'**
  String get exportPhotoDialogTitle;

  /// No description provided for @exportRapidLabel.
  ///
  /// In en, this message translates to:
  /// **'Rapid export'**
  String get exportRapidLabel;

  /// No description provided for @exportRapidHint.
  ///
  /// In en, this message translates to:
  /// **'Compressed JPEG for social media'**
  String get exportRapidHint;

  /// No description provided for @exportRapidScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get exportRapidScaleLabel;

  /// No description provided for @exportRapidScaleResultLabel.
  ///
  /// In en, this message translates to:
  /// **'≈ {width} × {height} px'**
  String exportRapidScaleResultLabel(int width, int height);

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

  /// No description provided for @copyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButton;

  /// No description provided for @hideButton.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideButton;

  /// No description provided for @exportSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportSuccessMessage(String path);

  /// No description provided for @exportDoneStatus.
  ///
  /// In en, this message translates to:
  /// **'Done!'**
  String get exportDoneStatus;

  /// No description provided for @exportFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailedStatus;

  /// No description provided for @aiDenoiseEnhanceFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'AI Enhance failed'**
  String get aiDenoiseEnhanceFailedStatus;

  /// No description provided for @exportFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailureMessage(String error);

  /// No description provided for @resetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetTooltip;

  /// No description provided for @settingsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsDialogTitle;

  /// No description provided for @settingsTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsTabGeneral;

  /// No description provided for @settingsTabPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settingsTabPerformance;

  /// No description provided for @settingsTabColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get settingsTabColor;

  /// No description provided for @settingsTabData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsTabData;

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

  /// No description provided for @settingsLanguageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get settingsLanguageGerman;

  /// No description provided for @settingsFastPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Fast preview while dragging sliders'**
  String get settingsFastPreviewLabel;

  /// No description provided for @settingsPreviewResolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview resolution'**
  String get settingsPreviewResolutionLabel;

  /// No description provided for @settingsPreviewResolutionHint.
  ///
  /// In en, this message translates to:
  /// **'Lower is faster to open and edit photos; export always uses the full sensor resolution'**
  String get settingsPreviewResolutionHint;

  /// No description provided for @settingsRawOnlyLabel.
  ///
  /// In en, this message translates to:
  /// **'RAW files only'**
  String get settingsRawOnlyLabel;

  /// No description provided for @settingsRawOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Hide JPEG, PNG and other common image formats from the library'**
  String get settingsRawOnlyHint;

  /// No description provided for @settingsAnimationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Interface animations'**
  String get settingsAnimationsLabel;

  /// No description provided for @settingsAnimationsHint.
  ///
  /// In en, this message translates to:
  /// **'Smooth transitions for panel sections, tab switches, zoom, and the preview after an edit'**
  String get settingsAnimationsHint;

  /// No description provided for @settingsGpuRenderLabel.
  ///
  /// In en, this message translates to:
  /// **'Use GPU rendering (experimental)'**
  String get settingsGpuRenderLabel;

  /// No description provided for @settingsGpuRenderHint.
  ///
  /// In en, this message translates to:
  /// **'Renders on the graphics card instead of the CPU; falls back automatically if unsupported'**
  String get settingsGpuRenderHint;

  /// No description provided for @settingsDynamicFullPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Dynamic full-resolution preview'**
  String get settingsDynamicFullPreviewLabel;

  /// No description provided for @settingsDynamicFullPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'A moment after an edit settles, re-render at the sensor\'s native resolution so a zoomed-in view sharpens up. Decoded sources are cached to disk.'**
  String get settingsDynamicFullPreviewHint;

  /// No description provided for @settingsFullQualityScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview resolution'**
  String get settingsFullQualityScaleLabel;

  /// No description provided for @settingsBaseContrastLabel.
  ///
  /// In en, this message translates to:
  /// **'darkmoon Color profile'**
  String get settingsBaseContrastLabel;

  /// No description provided for @settingsBaseContrastHint.
  ///
  /// In en, this message translates to:
  /// **'A fixed contrast curve applied to every photo before your edits — darkmoon\'s stand-in for the profile contrast Lightroom bakes in. Raise it if imported Lightroom presets look flat, lower it (0 = off) for a neutral starting point. Changes every photo and preset.'**
  String get settingsBaseContrastHint;

  /// No description provided for @settingsThumbnailThreadsLabel.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail loading threads'**
  String get settingsThumbnailThreadsLabel;

  /// No description provided for @settingsCustomDenoiseModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom denoise model'**
  String get settingsCustomDenoiseModelLabel;

  /// No description provided for @settingsCustomDenoiseModelHint.
  ///
  /// In en, this message translates to:
  /// **'Replaces the on-device Denoise model in the AI Denoise dialog\'s Enhance tab. Must be a drop-in replacement: 3-channel RGB, same-resolution in/out, \"input\"/\"output\" tensor names, [0,1]-normalized — a model that doesn\'t match will error or produce visibly wrong output, not a clean failure.'**
  String get settingsCustomDenoiseModelHint;

  /// No description provided for @settingsCustomDenoiseModelDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (RealPLKSR)'**
  String get settingsCustomDenoiseModelDefault;

  /// No description provided for @settingsCustomDenoiseModelPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a denoise model (.onnx)'**
  String get settingsCustomDenoiseModelPickerTitle;

  /// No description provided for @settingsCustomDenoiseModelChooseButton.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get settingsCustomDenoiseModelChooseButton;

  /// No description provided for @settingsCustomDenoiseModelResetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsCustomDenoiseModelResetButton;

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

  /// No description provided for @settingsDevLoggingLabel.
  ///
  /// In en, this message translates to:
  /// **'Developer mode'**
  String get settingsDevLoggingLabel;

  /// No description provided for @settingsDevLoggingHint.
  ///
  /// In en, this message translates to:
  /// **'Writes a detailed log to disk (errors, AI Enhance GPU/CPU status, etc.) for bug reports. Off by default.'**
  String get settingsDevLoggingHint;

  /// No description provided for @settingsOpenLogFolderButton.
  ///
  /// In en, this message translates to:
  /// **'Open log folder'**
  String get settingsOpenLogFolderButton;

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

  /// No description provided for @filmstripResetEditsAction.
  ///
  /// In en, this message translates to:
  /// **'Reset all edits'**
  String get filmstripResetEditsAction;

  /// No description provided for @filmstripShowOnDiskAction.
  ///
  /// In en, this message translates to:
  /// **'Show on disk'**
  String get filmstripShowOnDiskAction;

  /// No description provided for @filmstripDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get filmstripDeleteAction;

  /// No description provided for @imageContextCopyEditsAction.
  ///
  /// In en, this message translates to:
  /// **'Copy Edits'**
  String get imageContextCopyEditsAction;

  /// No description provided for @imageContextPasteEditsAction.
  ///
  /// In en, this message translates to:
  /// **'Paste Edits'**
  String get imageContextPasteEditsAction;

  /// No description provided for @filmstripResetEditsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset all edits?'**
  String get filmstripResetEditsConfirmTitle;

  /// No description provided for @filmstripResetEditsConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This resets \"{name}\" back to its untouched state — every adjustment, curve, and mask. This can\'t be undone.'**
  String filmstripResetEditsConfirmMessage(String name);

  /// No description provided for @filmstripDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get filmstripDeleteConfirmTitle;

  /// No description provided for @filmstripDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This sends \"{name}\" to the Recycle Bin and deletes its saved edits. You can restore the photo from the Recycle Bin, but not its edits.'**
  String filmstripDeleteConfirmMessage(String name);

  /// No description provided for @filmstripDeleteFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete \"{name}\": {error}'**
  String filmstripDeleteFailedMessage(String name, String error);

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

  /// No description provided for @sectionEffects.
  ///
  /// In en, this message translates to:
  /// **'EFFECTS'**
  String get sectionEffects;

  /// No description provided for @gradeRangeMidtones.
  ///
  /// In en, this message translates to:
  /// **'Midtones'**
  String get gradeRangeMidtones;

  /// No description provided for @gradeRangeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get gradeRangeGlobal;

  /// No description provided for @maskImageLayer.
  ///
  /// In en, this message translates to:
  /// **'Full Image'**
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

  /// No description provided for @maskOpacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get maskOpacityLabel;

  /// No description provided for @maskOverlayOpacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Overlay Opacity'**
  String get maskOverlayOpacityLabel;

  /// No description provided for @maskCloneTooltip.
  ///
  /// In en, this message translates to:
  /// **'Duplicate mask'**
  String get maskCloneTooltip;

  /// No description provided for @maskCloneSuffix.
  ///
  /// In en, this message translates to:
  /// **'copy'**
  String get maskCloneSuffix;

  /// No description provided for @maskDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete mask'**
  String get maskDeleteTooltip;

  /// No description provided for @maskResetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset this mask'**
  String get maskResetTooltip;

  /// No description provided for @maskClearAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear all masks'**
  String get maskClearAllTooltip;

  /// No description provided for @maskOverlayVisibleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide mask overlay'**
  String get maskOverlayVisibleTooltip;

  /// No description provided for @maskOverlayHiddenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show mask overlay'**
  String get maskOverlayHiddenTooltip;

  /// No description provided for @maskDisableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Disable mask'**
  String get maskDisableTooltip;

  /// No description provided for @maskEnableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Enable mask'**
  String get maskEnableTooltip;

  /// No description provided for @masksTitle.
  ///
  /// In en, this message translates to:
  /// **'Masks'**
  String get masksTitle;

  /// No description provided for @histogramTitle.
  ///
  /// In en, this message translates to:
  /// **'Histogram'**
  String get histogramTitle;

  /// No description provided for @filmstripEditedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get filmstripEditedTooltip;

  /// No description provided for @maskBrushSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Brush Size'**
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

  /// No description provided for @maskLuminance.
  ///
  /// In en, this message translates to:
  /// **'Luminance Range'**
  String get maskLuminance;

  /// No description provided for @maskFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get maskFlow;

  /// No description provided for @luminanceToleranceLabel.
  ///
  /// In en, this message translates to:
  /// **'Tolerance'**
  String get luminanceToleranceLabel;

  /// No description provided for @luminanceFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get luminanceFeatherLabel;

  /// No description provided for @luminanceHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the image to pick a brightness'**
  String get luminanceHint;

  /// No description provided for @flowAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get flowAmountLabel;

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

  /// No description provided for @mixerModeMixerLabel.
  ///
  /// In en, this message translates to:
  /// **'Mixer'**
  String get mixerModeMixerLabel;

  /// No description provided for @mixerModeHslLabel.
  ///
  /// In en, this message translates to:
  /// **'HSL'**
  String get mixerModeHslLabel;

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

  /// No description provided for @wbModeAsShot.
  ///
  /// In en, this message translates to:
  /// **'As Shot'**
  String get wbModeAsShot;

  /// No description provided for @wbModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get wbModeAuto;

  /// No description provided for @wbModeDaylight.
  ///
  /// In en, this message translates to:
  /// **'Daylight'**
  String get wbModeDaylight;

  /// No description provided for @wbModeCloudy.
  ///
  /// In en, this message translates to:
  /// **'Cloudy'**
  String get wbModeCloudy;

  /// No description provided for @wbModeShade.
  ///
  /// In en, this message translates to:
  /// **'Shade'**
  String get wbModeShade;

  /// No description provided for @wbModeTungsten.
  ///
  /// In en, this message translates to:
  /// **'Tungsten'**
  String get wbModeTungsten;

  /// No description provided for @wbModeFluorescent.
  ///
  /// In en, this message translates to:
  /// **'Fluorescent'**
  String get wbModeFluorescent;

  /// No description provided for @wbModeFlash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get wbModeFlash;

  /// No description provided for @wbModeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get wbModeCustom;

  /// No description provided for @wbEyedropperTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pick a neutral gray to set white balance'**
  String get wbEyedropperTooltip;

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

  /// No description provided for @sliderSharpenAmount.
  ///
  /// In en, this message translates to:
  /// **'Sharpening'**
  String get sliderSharpenAmount;

  /// No description provided for @sliderSharpenRadius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get sliderSharpenRadius;

  /// No description provided for @sliderSharpenDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get sliderSharpenDetail;

  /// No description provided for @sliderSharpenMasking.
  ///
  /// In en, this message translates to:
  /// **'Masking'**
  String get sliderSharpenMasking;

  /// No description provided for @sliderVignetteAmount.
  ///
  /// In en, this message translates to:
  /// **'Vignette Amount'**
  String get sliderVignetteAmount;

  /// No description provided for @sliderVignetteMidpoint.
  ///
  /// In en, this message translates to:
  /// **'Vignette Midpoint'**
  String get sliderVignetteMidpoint;

  /// No description provided for @sliderVignetteFeather.
  ///
  /// In en, this message translates to:
  /// **'Vignette Feather'**
  String get sliderVignetteFeather;

  /// No description provided for @sliderGrainAmount.
  ///
  /// In en, this message translates to:
  /// **'Grain Amount'**
  String get sliderGrainAmount;

  /// No description provided for @sliderGrainSize.
  ///
  /// In en, this message translates to:
  /// **'Grain Size'**
  String get sliderGrainSize;

  /// No description provided for @sliderGrainRoughness.
  ///
  /// In en, this message translates to:
  /// **'Grain Roughness'**
  String get sliderGrainRoughness;

  /// No description provided for @sliderParamCurveShadows.
  ///
  /// In en, this message translates to:
  /// **'Shadows'**
  String get sliderParamCurveShadows;

  /// No description provided for @sliderParamCurveDarks.
  ///
  /// In en, this message translates to:
  /// **'Darks'**
  String get sliderParamCurveDarks;

  /// No description provided for @sliderParamCurveLights.
  ///
  /// In en, this message translates to:
  /// **'Lights'**
  String get sliderParamCurveLights;

  /// No description provided for @sliderParamCurveHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get sliderParamCurveHighlights;

  /// No description provided for @sliderParamCurveShadowSplit.
  ///
  /// In en, this message translates to:
  /// **'Shadow Split'**
  String get sliderParamCurveShadowSplit;

  /// No description provided for @sliderParamCurveMidtoneSplit.
  ///
  /// In en, this message translates to:
  /// **'Midtone Split'**
  String get sliderParamCurveMidtoneSplit;

  /// No description provided for @sliderParamCurveHighlightSplit.
  ///
  /// In en, this message translates to:
  /// **'Highlight Split'**
  String get sliderParamCurveHighlightSplit;

  /// No description provided for @toneCurveParametricLabel.
  ///
  /// In en, this message translates to:
  /// **'Parametric'**
  String get toneCurveParametricLabel;

  /// No description provided for @sectionLensCorrection.
  ///
  /// In en, this message translates to:
  /// **'LENS CORRECTION'**
  String get sectionLensCorrection;

  /// No description provided for @lensCorrectionNoProfileFound.
  ///
  /// In en, this message translates to:
  /// **'No profile found'**
  String get lensCorrectionNoProfileFound;

  /// No description provided for @lensCorrectionProfileLabel.
  ///
  /// In en, this message translates to:
  /// **'Lens Profile'**
  String get lensCorrectionProfileLabel;

  /// No description provided for @lensCorrectionAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get lensCorrectionAutoDetect;

  /// No description provided for @lensCorrectionDistortionLabel.
  ///
  /// In en, this message translates to:
  /// **'Distortion'**
  String get lensCorrectionDistortionLabel;

  /// No description provided for @lensCorrectionVignetteLabel.
  ///
  /// In en, this message translates to:
  /// **'Vignetting'**
  String get lensCorrectionVignetteLabel;

  /// No description provided for @lensCorrectionChromaticAberrationLabel.
  ///
  /// In en, this message translates to:
  /// **'Chromatic Aberration'**
  String get lensCorrectionChromaticAberrationLabel;

  /// No description provided for @lensCorrectionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search lenses…'**
  String get lensCorrectionSearchHint;

  /// No description provided for @lensCorrectionSearchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get lensCorrectionSearchNoMatches;
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
      <String>['de', 'en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
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
