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

  /// No description provided for @menuOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get menuOpenFile;

  /// No description provided for @menuOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Add album folder'**
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

  /// No description provided for @tabAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get tabAlbums;

  /// No description provided for @tabEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get tabEditor;

  /// No description provided for @libraryDetailsSection.
  ///
  /// In en, this message translates to:
  /// **'DETAILS'**
  String get libraryDetailsSection;

  /// No description provided for @libraryDetailsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Select a photo to see its details'**
  String get libraryDetailsEmpty;

  /// No description provided for @libraryTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get libraryTagsLabel;

  /// No description provided for @libraryNoTags.
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get libraryNoTags;

  /// No description provided for @libraryHiddenByRawOnly.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo in this album is hidden because \"RAW files only\" is on} other{{count} photos in this album are hidden because \"RAW files only\" is on}}'**
  String libraryHiddenByRawOnly(int count);

  /// No description provided for @libraryShowAllFormats.
  ///
  /// In en, this message translates to:
  /// **'Show all formats'**
  String get libraryShowAllFormats;

  /// No description provided for @libraryUnsupportedFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file in this album is in a format this app cannot open} other{{count} files in this album are in formats this app cannot open}}'**
  String libraryUnsupportedFiles(int count);

  /// No description provided for @sidebarNewAlbumAction.
  ///
  /// In en, this message translates to:
  /// **'New album here…'**
  String get sidebarNewAlbumAction;

  /// No description provided for @sidebarDeleteAlbumAction.
  ///
  /// In en, this message translates to:
  /// **'Delete album…'**
  String get sidebarDeleteAlbumAction;

  /// No description provided for @libraryDeleteAlbumConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete album?'**
  String get libraryDeleteAlbumConfirmTitle;

  /// No description provided for @libraryDeleteAlbumConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This sends the album \"{name}\" and everything in it to the Recycle Bin, and deletes the saved edits of its photos.'**
  String libraryDeleteAlbumConfirmMessage(String name);

  /// No description provided for @libraryBackFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back to the previous album'**
  String get libraryBackFolderTooltip;

  /// No description provided for @menuLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get menuLibrary;

  /// No description provided for @libraryBackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back to the editor'**
  String get libraryBackTooltip;

  /// No description provided for @librarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search file names'**
  String get librarySearchHint;

  /// No description provided for @libraryMinRatingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show photos rated {stars} stars or more'**
  String libraryMinRatingTooltip(int stars);

  /// No description provided for @libraryAllLabelsTooltip.
  ///
  /// In en, this message translates to:
  /// **'All labels'**
  String get libraryAllLabelsTooltip;

  /// No description provided for @libraryPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No photos} =1{1 photo} other{{count} photos}}'**
  String libraryPhotoCount(int count);

  /// No description provided for @libraryEmptyFolders.
  ///
  /// In en, this message translates to:
  /// **'Add a folder to the library to browse it here'**
  String get libraryEmptyFolders;

  /// No description provided for @libraryAddFolder.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get libraryAddFolder;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No photos in this folder'**
  String get libraryEmpty;

  /// No description provided for @libraryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No photos match the filters'**
  String get libraryNoMatches;

  /// No description provided for @libraryOpenInEditor.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get libraryOpenInEditor;

  /// No description provided for @libraryNewAlbumTitle.
  ///
  /// In en, this message translates to:
  /// **'New album'**
  String get libraryNewAlbumTitle;

  /// No description provided for @libraryNewAlbumTooltip.
  ///
  /// In en, this message translates to:
  /// **'New album inside this one'**
  String get libraryNewAlbumTooltip;

  /// No description provided for @libraryConvertNegativeAction.
  ///
  /// In en, this message translates to:
  /// **'Convert negative…'**
  String get libraryConvertNegativeAction;

  /// No description provided for @libraryConvertNegativesAction.
  ///
  /// In en, this message translates to:
  /// **'Convert {count} negatives…'**
  String libraryConvertNegativesAction(int count);

  /// No description provided for @negativeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Negative conversion'**
  String get negativeDialogTitle;

  /// No description provided for @negativeColorTimingLabel.
  ///
  /// In en, this message translates to:
  /// **'Colour timing'**
  String get negativeColorTimingLabel;

  /// No description provided for @negativeRedLabel.
  ///
  /// In en, this message translates to:
  /// **'Red (cyan)'**
  String get negativeRedLabel;

  /// No description provided for @negativeGreenLabel.
  ///
  /// In en, this message translates to:
  /// **'Green (magenta)'**
  String get negativeGreenLabel;

  /// No description provided for @negativeBlueLabel.
  ///
  /// In en, this message translates to:
  /// **'Blue (yellow)'**
  String get negativeBlueLabel;

  /// No description provided for @negativePrintGradeLabel.
  ///
  /// In en, this message translates to:
  /// **'Print grade'**
  String get negativePrintGradeLabel;

  /// No description provided for @negativeExposureLabel.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get negativeExposureLabel;

  /// No description provided for @negativeContrastLabel.
  ///
  /// In en, this message translates to:
  /// **'Contrast (grade)'**
  String get negativeContrastLabel;

  /// No description provided for @negativeCompareHint.
  ///
  /// In en, this message translates to:
  /// **'Press and hold the preview to see the original negative.'**
  String get negativeCompareHint;

  /// No description provided for @negativeOriginalLabel.
  ///
  /// In en, this message translates to:
  /// **'Original negative'**
  String get negativeOriginalLabel;

  /// No description provided for @negativePreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No preview for this photo yet.'**
  String get negativePreviewUnavailable;

  /// No description provided for @negativeConvertButton.
  ///
  /// In en, this message translates to:
  /// **'Convert & save'**
  String get negativeConvertButton;

  /// No description provided for @negativeConvertAllButton.
  ///
  /// In en, this message translates to:
  /// **'Convert & save all ({count})'**
  String negativeConvertAllButton(int count);

  /// No description provided for @negativeConvertingProgress.
  ///
  /// In en, this message translates to:
  /// **'Converting {current}/{total}…'**
  String negativeConvertingProgress(int current, int total);

  /// No description provided for @negativeSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Saved 1 positive} other{Saved {count} positives}} beside the originals (_Positive.tiff).'**
  String negativeSavedMessage(int count);

  /// No description provided for @negativeFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not convert {name}.'**
  String negativeFailedMessage(String name);

  /// No description provided for @libraryMoveToAction.
  ///
  /// In en, this message translates to:
  /// **'Move to album…'**
  String get libraryMoveToAction;

  /// No description provided for @libraryNewAlbumFromSelection.
  ///
  /// In en, this message translates to:
  /// **'New album with these photos…'**
  String get libraryNewAlbumFromSelection;

  /// No description provided for @libraryPickAlbumTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to album'**
  String get libraryPickAlbumTitle;

  /// No description provided for @libraryPickAlbumConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get libraryPickAlbumConfirm;

  /// No description provided for @libraryMoveSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo not moved: a file with that name already exists there} other{{count} photos not moved: files with those names already exist there}}'**
  String libraryMoveSkipped(int count);

  /// No description provided for @libraryMovingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Moving photos... ({done}/{total})'**
  String libraryMovingPhotos(int done, int total);

  /// No description provided for @libraryFolderExists.
  ///
  /// In en, this message translates to:
  /// **'An album with that name already exists there'**
  String get libraryFolderExists;

  /// No description provided for @libraryEditTagsAction.
  ///
  /// In en, this message translates to:
  /// **'Edit tags…'**
  String get libraryEditTagsAction;

  /// No description provided for @libraryEditTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags, separated by commas'**
  String get libraryEditTagsTitle;

  /// No description provided for @librarySelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total} selected'**
  String librarySelectedCount(int selected, int total);

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

  /// No description provided for @aboutThirdPartyLicenses.
  ///
  /// In en, this message translates to:
  /// **'Third-party licences'**
  String get aboutThirdPartyLicenses;

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

  /// No description provided for @sidebarOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open a file or add a folder'**
  String get sidebarOpenTooltip;

  /// No description provided for @sidebarFoldersSection.
  ///
  /// In en, this message translates to:
  /// **'ALBUMS'**
  String get sidebarFoldersSection;

  /// No description provided for @sidebarRemoveFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove album from the library'**
  String get sidebarRemoveFolderTooltip;

  /// No description provided for @sidebarRemoveRecentFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent files'**
  String get sidebarRemoveRecentFileTooltip;

  /// No description provided for @sidebarFolderNotFoundTooltip.
  ///
  /// In en, this message translates to:
  /// **'Album not found — remove it from the list'**
  String get sidebarFolderNotFoundTooltip;

  /// No description provided for @sidebarPresetsSection.
  ///
  /// In en, this message translates to:
  /// **'PRESETS'**
  String get sidebarPresetsSection;

  /// No description provided for @presetImportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import presets (.xmp, .zip, .lrtemplate, .pp3, .costyle)'**
  String get presetImportTooltip;

  /// No description provided for @presetSaveNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save current edits as a preset'**
  String get presetSaveNewTooltip;

  /// No description provided for @presetTypeBadge.
  ///
  /// In en, this message translates to:
  /// **'PRESET'**
  String get presetTypeBadge;

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
  /// **'Color Profile Strength'**
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

  /// No description provided for @cropGuidedLabel.
  ///
  /// In en, this message translates to:
  /// **'Guided'**
  String get cropGuidedLabel;

  /// No description provided for @cropGuidedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Draw a line that should be level or plumb'**
  String get cropGuidedTooltip;

  /// No description provided for @cropGuidedHint.
  ///
  /// In en, this message translates to:
  /// **'Drag along an edge that should be perfectly horizontal or vertical — release to level it.'**
  String get cropGuidedHint;

  /// No description provided for @cropConstrainLabel.
  ///
  /// In en, this message translates to:
  /// **'Constrain crop'**
  String get cropConstrainLabel;

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

  /// No description provided for @colorizeButton.
  ///
  /// In en, this message translates to:
  /// **'Colorize'**
  String get colorizeButton;

  /// No description provided for @colorizeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Colorize'**
  String get colorizeDialogTitle;

  /// No description provided for @colorizeDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Add color to a black & white or faded photo, using AI. Works best on real daylight photos — may look off on night or artificially-lit scenes.'**
  String get colorizeDialogMessage;

  /// No description provided for @colorizeIntensityLabel.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get colorizeIntensityLabel;

  /// No description provided for @colorizeRemoveButton.
  ///
  /// In en, this message translates to:
  /// **'Remove colorization'**
  String get colorizeRemoveButton;

  /// No description provided for @colorizeFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Colorize couldn\'t run on this photo. It\'s been turned back off.'**
  String get colorizeFailedMessage;

  /// No description provided for @colorizeFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Colorize failed'**
  String get colorizeFailedStatus;

  /// No description provided for @removeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove objects'**
  String get removeButton;

  /// No description provided for @removeUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Turn off AI Enhance, Cloud AI or Colorize before removing objects.'**
  String get removeUnavailableMessage;

  /// No description provided for @removePanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove objects'**
  String get removePanelTitle;

  /// No description provided for @removePanelHint.
  ///
  /// In en, this message translates to:
  /// **'Paint over what should go, then press Remove. The area is filled from its surroundings.'**
  String get removePanelHint;

  /// No description provided for @removeRunButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeRunButton;

  /// No description provided for @removeClearStrokes.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get removeClearStrokes;

  /// No description provided for @removeDoneButton.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get removeDoneButton;

  /// No description provided for @removeRunningMessage.
  ///
  /// In en, this message translates to:
  /// **'Removing…'**
  String get removeRunningMessage;

  /// No description provided for @removeRunningProgress.
  ///
  /// In en, this message translates to:
  /// **'Removing… ({done}/{total})'**
  String removeRunningProgress(int done, int total);

  /// No description provided for @removeFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The removal could not be computed. The model file may be missing.'**
  String get removeFailedMessage;

  /// No description provided for @removeFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Removal failed'**
  String get removeFailedStatus;

  /// No description provided for @removePatchName.
  ///
  /// In en, this message translates to:
  /// **'Removal {n}'**
  String removePatchName(int n);

  /// No description provided for @removeGrowLabel.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get removeGrowLabel;

  /// No description provided for @removeWithMaskLabel.
  ///
  /// In en, this message translates to:
  /// **'Or remove what a mask covers'**
  String get removeWithMaskLabel;

  /// No description provided for @removeWithMaskPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Remove with a mask…'**
  String get removeWithMaskPlaceholder;

  /// No description provided for @removeListTitle.
  ///
  /// In en, this message translates to:
  /// **'Removals'**
  String get removeListTitle;

  /// No description provided for @removeVisibleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Applied — click to hide'**
  String get removeVisibleTooltip;

  /// No description provided for @removeHiddenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hidden — click to apply'**
  String get removeHiddenTooltip;

  /// No description provided for @removeDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete this removal'**
  String get removeDeleteTooltip;

  /// No description provided for @removeMaskNotReadyMessage.
  ///
  /// In en, this message translates to:
  /// **'That mask is still being computed. Try again in a moment.'**
  String get removeMaskNotReadyMessage;

  /// No description provided for @removeModeAi.
  ///
  /// In en, this message translates to:
  /// **'AI fill'**
  String get removeModeAi;

  /// No description provided for @removeModeClone.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get removeModeClone;

  /// No description provided for @removeModeHeal.
  ///
  /// In en, this message translates to:
  /// **'Heal'**
  String get removeModeHeal;

  /// No description provided for @removeModeGenerative.
  ///
  /// In en, this message translates to:
  /// **'Generative'**
  String get removeModeGenerative;

  /// No description provided for @removePickSourceButton.
  ///
  /// In en, this message translates to:
  /// **'Pick source'**
  String get removePickSourceButton;

  /// No description provided for @removePickSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Click the photo where the patch should copy from.'**
  String get removePickSourceHint;

  /// No description provided for @removeSourceDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'Source: beside the patch (or pick one).'**
  String get removeSourceDefaultHint;

  /// No description provided for @removeSourcePickedHint.
  ///
  /// In en, this message translates to:
  /// **'Source set.'**
  String get removeSourcePickedHint;

  /// No description provided for @removePromptLabel.
  ///
  /// In en, this message translates to:
  /// **'What should be there instead'**
  String get removePromptLabel;

  /// No description provided for @removePromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. grass, sky, wall'**
  String get removePromptHint;

  /// No description provided for @removeGenerativeNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Set the generative server address in Settings (AI tab) first.'**
  String get removeGenerativeNotConfigured;

  /// No description provided for @removeGenerativeFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The generative server did not return a patch: {error}'**
  String removeGenerativeFailedMessage(String error);

  /// No description provided for @removeCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 removal applied} other{{count} removals applied}}'**
  String removeCountLabel(int count);

  /// No description provided for @colorizeCpuWarning.
  ///
  /// In en, this message translates to:
  /// **'Colorize is running on the CPU (no compatible GPU found) — this will be slower than usual.'**
  String get colorizeCpuWarning;

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

  /// No description provided for @colorizeStartingMessage.
  ///
  /// In en, this message translates to:
  /// **'Running Colorize...'**
  String get colorizeStartingMessage;

  /// No description provided for @colorizeApplyingMessage.
  ///
  /// In en, this message translates to:
  /// **'Applying Colorize...'**
  String get colorizeApplyingMessage;

  /// No description provided for @colorizeDisablingMessage.
  ///
  /// In en, this message translates to:
  /// **'Disabling Colorize...'**
  String get colorizeDisablingMessage;

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

  /// No description provided for @aiDenoiseEnhanceRestoreDetailLabel.
  ///
  /// In en, this message translates to:
  /// **'Restore detail'**
  String get aiDenoiseEnhanceRestoreDetailLabel;

  /// No description provided for @aiDenoiseEnhanceDetailSharpenLabel.
  ///
  /// In en, this message translates to:
  /// **'Sharpen detail'**
  String get aiDenoiseEnhanceDetailSharpenLabel;

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

  /// No description provided for @aiDenoiseEnhanceStageDetailRestore.
  ///
  /// In en, this message translates to:
  /// **'Restoring detail'**
  String get aiDenoiseEnhanceStageDetailRestore;

  /// No description provided for @aiDenoiseEnhanceStageDetailSharpen.
  ///
  /// In en, this message translates to:
  /// **'Sharpening detail'**
  String get aiDenoiseEnhanceStageDetailSharpen;

  /// No description provided for @aiDenoiseEnhanceStageSharpen.
  ///
  /// In en, this message translates to:
  /// **'Sharpening'**
  String get aiDenoiseEnhanceStageSharpen;

  /// No description provided for @aiDenoiseEnhanceStageColorize.
  ///
  /// In en, this message translates to:
  /// **'Colorizing'**
  String get aiDenoiseEnhanceStageColorize;

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

  /// No description provided for @photoStageOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening file...'**
  String get photoStageOpening;

  /// No description provided for @photoStageUnpacking.
  ///
  /// In en, this message translates to:
  /// **'Reading sensor data...'**
  String get photoStageUnpacking;

  /// No description provided for @photoStageProcessing.
  ///
  /// In en, this message translates to:
  /// **'Developing...'**
  String get photoStageProcessing;

  /// No description provided for @photoStageExtracting.
  ///
  /// In en, this message translates to:
  /// **'Preparing image...'**
  String get photoStageExtracting;

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

  /// No description provided for @exportFrameLabel.
  ///
  /// In en, this message translates to:
  /// **'Frame'**
  String get exportFrameLabel;

  /// No description provided for @exportFrameHint.
  ///
  /// In en, this message translates to:
  /// **'A border around the photo in the exported file'**
  String get exportFrameHint;

  /// No description provided for @exportFramePaddingLabel.
  ///
  /// In en, this message translates to:
  /// **'Border'**
  String get exportFramePaddingLabel;

  /// No description provided for @exportFrameRadiusLabel.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get exportFrameRadiusLabel;

  /// No description provided for @exportFrameAspectLabel.
  ///
  /// In en, this message translates to:
  /// **'Frame shape'**
  String get exportFrameAspectLabel;

  /// No description provided for @exportFrameAspectOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get exportFrameAspectOriginal;

  /// No description provided for @exportFrameBackgroundLabel.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get exportFrameBackgroundLabel;

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

  /// No description provided for @settingsPreviewResolutionNative.
  ///
  /// In en, this message translates to:
  /// **'Native'**
  String get settingsPreviewResolutionNative;

  /// No description provided for @settingsPreviewResolutionHint.
  ///
  /// In en, this message translates to:
  /// **'Lower is faster to open and edit photos; export always uses the full sensor resolution'**
  String get settingsPreviewResolutionHint;

  /// No description provided for @settingsEditEmbeddedJpegLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit the camera\'s JPEG'**
  String get settingsEditEmbeddedJpegLabel;

  /// No description provided for @settingsEditEmbeddedJpegHint.
  ///
  /// In en, this message translates to:
  /// **'Edit a RAW as the camera\'s own JPEG rendering rather than as sensor data. It opens faster and starts from the look the camera intended, but a rendered 8-bit image has far less latitude to recover a blown sky or a crushed shadow.'**
  String get settingsEditEmbeddedJpegHint;

  /// No description provided for @settingsCacheStorageLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache storage'**
  String get settingsCacheStorageLabel;

  /// No description provided for @settingsCacheMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring...'**
  String get settingsCacheMeasuring;

  /// No description provided for @settingsCacheUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit}'**
  String settingsCacheUsedOf(String used, String limit);

  /// No description provided for @settingsCachePreviews.
  ///
  /// In en, this message translates to:
  /// **'Previews'**
  String get settingsCachePreviews;

  /// No description provided for @settingsCacheFullSources.
  ///
  /// In en, this message translates to:
  /// **'Full-resolution sources'**
  String get settingsCacheFullSources;

  /// No description provided for @settingsCacheThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get settingsCacheThumbnails;

  /// No description provided for @settingsCacheAiResults.
  ///
  /// In en, this message translates to:
  /// **'AI results'**
  String get settingsCacheAiResults;

  /// No description provided for @settingsCacheLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache limit'**
  String get settingsCacheLimitLabel;

  /// No description provided for @settingsCacheLimitUnlimited.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get settingsCacheLimitUnlimited;

  /// No description provided for @settingsCacheLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Previews and full-resolution sources are deleted oldest-first to stay under this. AI results are never deleted automatically — they cost minutes of processing to rebuild, not seconds.'**
  String get settingsCacheLimitHint;

  /// No description provided for @settingsClearCacheTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear {category}'**
  String settingsClearCacheTooltip(String category);

  /// No description provided for @settingsClearAllCachesButton.
  ///
  /// In en, this message translates to:
  /// **'Clear all caches'**
  String get settingsClearAllCachesButton;

  /// No description provided for @confirmClearCacheMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete every cached {category}? They are rebuilt as photos are opened again.'**
  String confirmClearCacheMessage(String category);

  /// No description provided for @confirmClearAiCacheMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete every cached AI result? These took minutes of processing each and running them again costs that time over, not a quick re-decode.'**
  String get confirmClearAiCacheMessage;

  /// No description provided for @confirmClearAllCachesMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete every cache, including AI results? Previews and thumbnails come back on their own; AI results have to be run again, which takes minutes per photo.'**
  String get confirmClearAllCachesMessage;

  /// No description provided for @settingsRawOnlyLabel.
  ///
  /// In en, this message translates to:
  /// **'RAW files only'**
  String get settingsRawOnlyLabel;

  /// No description provided for @settingsIncludeSubfoldersLabel.
  ///
  /// In en, this message translates to:
  /// **'Subfolder images'**
  String get settingsIncludeSubfoldersLabel;

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
  /// **'Use GPU rendering'**
  String get settingsGpuRenderLabel;

  /// No description provided for @settingsGpuRenderHint.
  ///
  /// In en, this message translates to:
  /// **'Renders on the graphics card instead of the CPU; falls back automatically if unsupported'**
  String get settingsGpuRenderHint;

  /// No description provided for @settingsXmpSidecarLabel.
  ///
  /// In en, this message translates to:
  /// **'Write XMP sidecar files'**
  String get settingsXmpSidecarLabel;

  /// No description provided for @settingsXmpSidecarHint.
  ///
  /// In en, this message translates to:
  /// **'Saves each photo\'s edits in a .xmp file next to it, so they follow the photo when it moves and can be read by other editors'**
  String get settingsXmpSidecarHint;

  /// No description provided for @settingsRemoveSidecarsButton.
  ///
  /// In en, this message translates to:
  /// **'Remove the .xmp files this app wrote'**
  String get settingsRemoveSidecarsButton;

  /// No description provided for @confirmRemoveSidecarsMessage.
  ///
  /// In en, this message translates to:
  /// **'This deletes every .xmp sidecar darkmoon wrote beside the photos in your library folders. Sidecars written by other applications are kept. Your edits stay in the catalog.'**
  String get confirmRemoveSidecarsMessage;

  /// No description provided for @removeSidecarsResultMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No darkmoon sidecars found} =1{Removed 1 sidecar} other{Removed {count} sidecars}}'**
  String removeSidecarsResultMessage(int count);

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
  /// **'Replaces the on-device Denoise model in the AI Denoise dialog\'s Enhance tab. Must be a drop-in replacement: 3-channel RGB, same-resolution in/out, [0,1]-normalized (tensor names are read from the model, so any naming works) — a model that doesn\'t match will error or produce visibly wrong output, not a clean failure.'**
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

  /// No description provided for @settingsGenerativeUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Generative replace server'**
  String get settingsGenerativeUrlLabel;

  /// No description provided for @settingsGenerativeUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Address of a Solstice-compatible inpainting middleware (ComfyUI behind it), used by the Generative fill of Remove objects. Nothing is bundled: leave empty to keep the mode off.'**
  String get settingsGenerativeUrlHint;

  /// No description provided for @settingsGenerativeUrlPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'http://127.0.0.1:8000'**
  String get settingsGenerativeUrlPlaceholder;

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

  /// No description provided for @settingsPruneMissingButton.
  ///
  /// In en, this message translates to:
  /// **'Remove missing photos from catalog'**
  String get settingsPruneMissingButton;

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

  /// No description provided for @confirmPruneMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes saved edits, curves, masks, presets, and recent-file entries for photos that no longer exist on disk. This can\'t be undone.'**
  String get confirmPruneMissingMessage;

  /// No description provided for @pruneMissingResultMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No missing photos found} =1{Removed 1 missing photo from the catalog} other{Removed {count} missing photos from the catalog}}'**
  String pruneMissingResultMessage(int count);

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

  /// No description provided for @filmstripRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get filmstripRatingLabel;

  /// No description provided for @filmstripColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color label'**
  String get filmstripColorLabel;

  /// No description provided for @labelNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get labelNone;

  /// No description provided for @labelRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get labelRed;

  /// No description provided for @labelYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get labelYellow;

  /// No description provided for @labelGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get labelGreen;

  /// No description provided for @labelBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get labelBlue;

  /// No description provided for @labelPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get labelPurple;

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

  /// No description provided for @filmstripDeleteConfirmManyMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{This sends {count} photos to the Recycle Bin and deletes their saved edits. You can restore the photos from the Recycle Bin, but not their edits.}}'**
  String filmstripDeleteConfirmManyMessage(int count);

  /// No description provided for @filmstripDeleteFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete \"{name}\": {error}'**
  String filmstripDeleteFailedMessage(String name, String error);

  /// No description provided for @sectionColorProfile.
  ///
  /// In en, this message translates to:
  /// **'COLOR PROFILE'**
  String get sectionColorProfile;

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

  /// No description provided for @sectionFilm.
  ///
  /// In en, this message translates to:
  /// **'FILM'**
  String get sectionFilm;

  /// No description provided for @filmNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get filmNone;

  /// No description provided for @filmImportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import LUTs (.cube, Hald CLUT image)'**
  String get filmImportTooltip;

  /// No description provided for @filmImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import LUTs'**
  String get filmImportDialogTitle;

  /// No description provided for @filmImportedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 LUT} other{Imported {count} LUTs}} into the Film list.'**
  String filmImportedMessage(int count);

  /// No description provided for @filmImportFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not import {name}: {error}'**
  String filmImportFailedMessage(String name, String error);

  /// No description provided for @sliderFilmAmount.
  ///
  /// In en, this message translates to:
  /// **'Film Amount'**
  String get sliderFilmAmount;

  /// No description provided for @colorizeFilmLabel.
  ///
  /// In en, this message translates to:
  /// **'Film look'**
  String get colorizeFilmLabel;

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
  /// **'Original Image'**
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

  /// No description provided for @maskOkButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get maskOkButton;

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

  /// No description provided for @histogramShadowClipping.
  ///
  /// In en, this message translates to:
  /// **'Shadows clipped: {percent}% of the frame'**
  String histogramShadowClipping(String percent);

  /// No description provided for @histogramHighlightClipping.
  ///
  /// In en, this message translates to:
  /// **'Highlights clipped: {percent}% of the frame'**
  String histogramHighlightClipping(String percent);

  /// No description provided for @histogramNoShadowClipping.
  ///
  /// In en, this message translates to:
  /// **'No shadow clipping'**
  String get histogramNoShadowClipping;

  /// No description provided for @histogramNoHighlightClipping.
  ///
  /// In en, this message translates to:
  /// **'No highlight clipping'**
  String get histogramNoHighlightClipping;

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

  /// No description provided for @aiMaskFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get aiMaskFeatherLabel;

  /// No description provided for @radialFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get radialFeatherLabel;

  /// No description provided for @linearFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get linearFeatherLabel;

  /// No description provided for @colorRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the image to pick a color'**
  String get colorRangeHint;

  /// No description provided for @maskWholeImage.
  ///
  /// In en, this message translates to:
  /// **'Whole Image'**
  String get maskWholeImage;

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

  /// No description provided for @maskSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get maskSubject;

  /// No description provided for @maskSky.
  ///
  /// In en, this message translates to:
  /// **'Sky'**
  String get maskSky;

  /// No description provided for @maskForeground.
  ///
  /// In en, this message translates to:
  /// **'Foreground'**
  String get maskForeground;

  /// No description provided for @maskDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get maskDepth;

  /// No description provided for @subjectMaskHint.
  ///
  /// In en, this message translates to:
  /// **'Drag a box around the subject, or tap it'**
  String get subjectMaskHint;

  /// No description provided for @depthNearLabel.
  ///
  /// In en, this message translates to:
  /// **'Near'**
  String get depthNearLabel;

  /// No description provided for @depthFarLabel.
  ///
  /// In en, this message translates to:
  /// **'Far'**
  String get depthFarLabel;

  /// No description provided for @depthFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get depthFeatherLabel;

  /// No description provided for @aiMaskComputing.
  ///
  /// In en, this message translates to:
  /// **'Detecting…'**
  String get aiMaskComputing;

  /// No description provided for @aiMaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Detection failed'**
  String get aiMaskFailed;

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

  /// No description provided for @sliderColorProfileAmount.
  ///
  /// In en, this message translates to:
  /// **'Color Profile Contrast'**
  String get sliderColorProfileAmount;

  /// No description provided for @colorProfileModeDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get colorProfileModeDefault;

  /// No description provided for @colorProfileModeFlat.
  ///
  /// In en, this message translates to:
  /// **'Vivid'**
  String get colorProfileModeFlat;

  /// No description provided for @colorProfileModeMissing.
  ///
  /// In en, this message translates to:
  /// **'Custom profile (not installed)'**
  String get colorProfileModeMissing;

  /// No description provided for @colorProfileMissingWarning.
  ///
  /// In en, this message translates to:
  /// **'This photo uses a custom colour profile that is not installed. Rendering with Default until it is imported — the photo still remembers which profile it wants.'**
  String get colorProfileMissingWarning;

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

  /// No description provided for @sliderCameraColor.
  ///
  /// In en, this message translates to:
  /// **'Camera Color'**
  String get sliderCameraColor;

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

  /// No description provided for @colorProfileEditorTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New colour profile'**
  String get colorProfileEditorTitleNew;

  /// No description provided for @colorProfileEditorTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit colour profile'**
  String get colorProfileEditorTitleEdit;

  /// No description provided for @colorProfileEditorTabColor.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colorProfileEditorTabColor;

  /// No description provided for @colorProfileEditorTabBase.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get colorProfileEditorTabBase;

  /// No description provided for @colorProfileEditorToneHint.
  ///
  /// In en, this message translates to:
  /// **'Remaps brightness while keeping colour. Drag a point to reshape, click empty space to add one, right-click to remove.'**
  String get colorProfileEditorToneHint;

  /// No description provided for @colorProfileEditorPhotoSlidersHint.
  ///
  /// In en, this message translates to:
  /// **'These two apply to the open photo, not to the profile — they are here because a curve only means something once you see how hard it is applied.'**
  String get colorProfileEditorPhotoSlidersHint;

  /// No description provided for @colorProfileEditorBasicHint.
  ///
  /// In en, this message translates to:
  /// **'Eight hue ranges. Each covers three of the profile\'s 24 bins.'**
  String get colorProfileEditorBasicHint;

  /// No description provided for @colorProfileEditorAdvancedHint.
  ///
  /// In en, this message translates to:
  /// **'All 24 hue bins, one every 15 degrees.'**
  String get colorProfileEditorAdvancedHint;

  /// No description provided for @colorProfileEditorModeBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get colorProfileEditorModeBasic;

  /// No description provided for @colorProfileEditorModeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get colorProfileEditorModeAdvanced;

  /// No description provided for @colorProfileEditorHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get colorProfileEditorHue;

  /// No description provided for @colorProfileEditorSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get colorProfileEditorSaturation;

  /// No description provided for @colorProfileEditorLuminance.
  ///
  /// In en, this message translates to:
  /// **'Luminance'**
  String get colorProfileEditorLuminance;

  /// No description provided for @colorProfileEditorNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get colorProfileEditorNameLabel;

  /// No description provided for @colorProfileEditorNameTaken.
  ///
  /// In en, this message translates to:
  /// **'A profile with this name already exists. Saving will add a number to keep them apart.'**
  String get colorProfileEditorNameTaken;

  /// No description provided for @colorProfileEditorResetHint.
  ///
  /// In en, this message translates to:
  /// **'Clears the tone curve and every hue adjustment. The name is kept.'**
  String get colorProfileEditorResetHint;

  /// No description provided for @colorProfileEditorReset.
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get colorProfileEditorReset;

  /// No description provided for @colorProfileNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create a colour profile'**
  String get colorProfileNewTooltip;

  /// No description provided for @hueRangeRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get hueRangeRed;

  /// No description provided for @hueRangeOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get hueRangeOrange;

  /// No description provided for @hueRangeYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get hueRangeYellow;

  /// No description provided for @hueRangeGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get hueRangeGreen;

  /// No description provided for @hueRangeAqua.
  ///
  /// In en, this message translates to:
  /// **'Aqua'**
  String get hueRangeAqua;

  /// No description provided for @hueRangeBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get hueRangeBlue;

  /// No description provided for @hueRangePurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get hueRangePurple;

  /// No description provided for @hueRangeMagenta.
  ///
  /// In en, this message translates to:
  /// **'Magenta'**
  String get hueRangeMagenta;

  /// No description provided for @colorProfileRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename colour profile'**
  String get colorProfileRenameTitle;

  /// No description provided for @colorProfileExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export colour profile'**
  String get colorProfileExportDialogTitle;

  /// No description provided for @colorProfileImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import colour profile'**
  String get colorProfileImportDialogTitle;

  /// No description provided for @colorProfileImportFailed.
  ///
  /// In en, this message translates to:
  /// **'That file could not be read as a colour profile.'**
  String get colorProfileImportFailed;

  /// No description provided for @colorProfileDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete colour profile'**
  String get colorProfileDeleteTitle;

  /// No description provided for @colorProfileDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Photos already using it will fall back to Default and say so, and will use it again if you import it back.'**
  String colorProfileDeleteMessage(String name);

  /// No description provided for @colorProfileMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Colour profile actions'**
  String get colorProfileMenuTooltip;

  /// No description provided for @colorProfileEditLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get colorProfileEditLabel;

  /// No description provided for @colorProfileDuplicateLabel.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get colorProfileDuplicateLabel;

  /// No description provided for @colorProfileImportLabel.
  ///
  /// In en, this message translates to:
  /// **'Import...'**
  String get colorProfileImportLabel;

  /// No description provided for @colorProfileEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Pick a colour from the photo'**
  String get colorProfileEyedropper;

  /// No description provided for @controlsTabAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get controlsTabAdjust;

  /// No description provided for @controlsTabColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get controlsTabColour;

  /// No description provided for @controlsTabEffects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get controlsTabEffects;

  /// No description provided for @settingsPanelLayoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Editing panel'**
  String get settingsPanelLayoutLabel;

  /// No description provided for @settingsPanelLayoutTabbed.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get settingsPanelLayoutTabbed;

  /// No description provided for @settingsPanelLayoutFlat.
  ///
  /// In en, this message translates to:
  /// **'One long list'**
  String get settingsPanelLayoutFlat;

  /// No description provided for @settingsTabStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Tab labels'**
  String get settingsTabStyleLabel;

  /// No description provided for @settingsTabStyleText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get settingsTabStyleText;

  /// No description provided for @settingsTabStyleIcons.
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get settingsTabStyleIcons;

  /// No description provided for @settingsPresetThumbnailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset previews'**
  String get settingsPresetThumbnailsLabel;

  /// No description provided for @settingsPresetThumbnailsHint.
  ///
  /// In en, this message translates to:
  /// **'Show each preset applied to the current photo'**
  String get settingsPresetThumbnailsHint;

  /// No description provided for @settingsPanelLayoutHint.
  ///
  /// In en, this message translates to:
  /// **'Tabs group the sections into Adjust, Colour and Effects. Masks stay pinned above them either way.'**
  String get settingsPanelLayoutHint;

  /// No description provided for @controlsTabDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get controlsTabDetails;

  /// No description provided for @transformLevelButton.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get transformLevelButton;

  /// No description provided for @transformLevelNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing straight enough to level by. Straighten by hand.'**
  String get transformLevelNothingFound;

  /// No description provided for @transformAutoButton.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get transformAutoButton;

  /// No description provided for @transformAutoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Level the photo and correct converging verticals'**
  String get transformAutoTooltip;

  /// No description provided for @transformVerticalButton.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get transformVerticalButton;

  /// No description provided for @transformVerticalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Level and correct converging verticals, even on faint evidence'**
  String get transformVerticalTooltip;

  /// No description provided for @transformFullButton.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get transformFullButton;

  /// No description provided for @transformFullTooltip.
  ///
  /// In en, this message translates to:
  /// **'Also correct converging horizontals — for architecture, since it will skew a landscape'**
  String get transformFullTooltip;

  /// No description provided for @transformAutoNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing straight enough to correct by. Adjust by hand.'**
  String get transformAutoNothingFound;
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
