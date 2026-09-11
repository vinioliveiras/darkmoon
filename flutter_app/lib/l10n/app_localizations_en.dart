// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get menuOpenFile => 'Open File';

  @override
  String get menuOpenFolder => 'Add Folder';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuAbout => 'About';

  @override
  String get menuLibrary => 'Library';

  @override
  String get libraryBackTooltip => 'Back to the editor';

  @override
  String get librarySearchHint => 'Search file names';

  @override
  String libraryMinRatingTooltip(int stars) {
    return 'Show photos rated $stars stars or more';
  }

  @override
  String get libraryAllLabelsTooltip => 'All labels';

  @override
  String libraryPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
      zero: 'No photos',
    );
    return '$_temp0';
  }

  @override
  String get libraryEmptyFolders =>
      'Add a folder to the library to browse it here';

  @override
  String get libraryAddFolder => 'Add folder';

  @override
  String get libraryEmpty => 'No photos in this folder';

  @override
  String get libraryNoMatches => 'No photos match the filters';

  @override
  String get libraryOpenInEditor => 'Edit';

  @override
  String get libraryNewAlbumTitle => 'New album';

  @override
  String get libraryNewAlbumTooltip => 'New album: a folder inside this one';

  @override
  String get libraryMoveToAction => 'Move to folder…';

  @override
  String libraryMoveSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count photos not moved: files with those names already exist there',
      one: '1 photo not moved: a file with that name already exists there',
    );
    return '$_temp0';
  }

  @override
  String get libraryFolderExists =>
      'A folder with that name already exists there';

  @override
  String get libraryEditTagsAction => 'Edit tags…';

  @override
  String get libraryEditTagsTitle => 'Tags, separated by commas';

  @override
  String librarySelectedCount(int selected, int total) {
    return '$selected of $total selected';
  }

  @override
  String get aboutDialogTitle => 'About darkmoon';

  @override
  String get aboutCredits => 'Developed by Vini';

  @override
  String get splashLicense => 'GNU Affero General Public License v3.0';

  @override
  String get aboutThirdPartyLicenses => 'Third-party licences';

  @override
  String get splashCopyright => '© 2026 Vini. Licensed under GNU AGPL v3.0.';

  @override
  String get splashLoading => 'Loading your library…';

  @override
  String get dialogOpenFolderTitle => 'Add Folder';

  @override
  String get dialogOpenFileTitle => 'Open RAW File';

  @override
  String get loadingFolder => 'Loading folder...';

  @override
  String loadingPhotos(int loaded, int total) {
    return 'Loading photos... ($loaded/$total)';
  }

  @override
  String loadingImage(String name) {
    return 'Loading $name...';
  }

  @override
  String get applyingAdjustments => 'Applying adjustments...';

  @override
  String get emptyStateOpenFolder =>
      'Open a folder with RAW files to get started';

  @override
  String get noFolderOpen => 'No folder open';

  @override
  String decodingPhoto(String name) {
    return '$name\n(decoding...)';
  }

  @override
  String photoNotFoundMessage(String name) {
    return '$name\ncan\'t be found — it may have been moved, renamed or deleted outside darkmoon';
  }

  @override
  String get sidebarRecentFilesSection => 'RECENT FILES';

  @override
  String get sidebarOpenTooltip => 'Open a file or add a folder';

  @override
  String get sidebarFoldersSection => 'FOLDERS';

  @override
  String get sidebarRemoveFolderTooltip => 'Remove folder';

  @override
  String get sidebarRemoveRecentFileTooltip => 'Remove from recent files';

  @override
  String get sidebarFolderNotFoundTooltip =>
      'Folder not found — remove it from the list';

  @override
  String get sidebarPresetsSection => 'PRESETS';

  @override
  String get presetImportTooltip => 'Import presets (.xmp or .zip)';

  @override
  String get presetSaveNewTooltip => 'Save current edits as a preset';

  @override
  String get presetTypeBadge => 'PRESET';

  @override
  String get presetEmptyHint => 'No presets yet';

  @override
  String presetAmountDialogTitle(String name) {
    return 'Apply \"$name\"';
  }

  @override
  String get presetAmountLabel => 'Color Profile Strength';

  @override
  String get presetAmountApplyButton => 'Apply';

  @override
  String get presetRenameLabel => 'Rename';

  @override
  String get presetExportLabel => 'Export';

  @override
  String get presetDeleteLabel => 'Delete';

  @override
  String get presetSaveLabel => 'Save';

  @override
  String get presetSaveNewTitle => 'Save preset';

  @override
  String get presetRenameTitle => 'Rename preset';

  @override
  String get presetExportDialogTitle => 'Export preset';

  @override
  String get presetExportManyTooltip => 'Export selected as .zip';

  @override
  String get presetExportManyDialogTitle => 'Export presets';

  @override
  String get presetImportDialogTitle => 'Import presets';

  @override
  String presetDeleteConfirmMessage(String name) {
    return 'Delete the preset \"$name\"? This can\'t be undone.';
  }

  @override
  String presetDeleteManyConfirmMessage(int count) {
    return 'Delete $count presets? This can\'t be undone.';
  }

  @override
  String get presetSelectTooltip => 'Select presets';

  @override
  String get presetSelectAllTooltip => 'Select all';

  @override
  String presetSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get beforeLabel => 'Before';

  @override
  String get afterLabel => 'After';

  @override
  String get zoomFit => 'Fit';

  @override
  String get fitToWindow => 'Fit to window';

  @override
  String get beforeAfterButton => 'Before/After';

  @override
  String get cropButton => 'Crop & Transform';

  @override
  String get sectionCropTransform => 'CROP & TRANSFORM';

  @override
  String get cropAspectLabel => 'Aspect';

  @override
  String get transformStraightenLabel => 'Straighten';

  @override
  String get transformVerticalLabel => 'Vertical';

  @override
  String get transformHorizontalLabel => 'Horizontal';

  @override
  String get transformAspectLabel => 'Aspect';

  @override
  String get transformScaleLabel => 'Scale';

  @override
  String get cropRotateLeftTooltip => 'Rotate 90° left';

  @override
  String get cropRotateRightTooltip => 'Rotate 90° right';

  @override
  String get cropGuidedLabel => 'Guided';

  @override
  String get cropGuidedTooltip => 'Draw a line that should be level or plumb';

  @override
  String get cropGuidedHint =>
      'Drag along an edge that should be perfectly horizontal or vertical — release to level it.';

  @override
  String get cropDoneButton => 'OK';

  @override
  String get undoButton => 'Undo';

  @override
  String get redoButton => 'Redo';

  @override
  String get aiDenoiseButton => 'AI Denoise';

  @override
  String get aiDenoiseDialogTitle => 'AI Denoise';

  @override
  String get aiDenoiseDialogMessage =>
      'Reduce noise automatically, tuned to keep detail sharp.';

  @override
  String get colorizeButton => 'Colorize';

  @override
  String get colorizeDialogTitle => 'Colorize';

  @override
  String get colorizeDialogMessage =>
      'Add color to a black & white or faded photo, using AI. Works best on real daylight photos — may look off on night or artificially-lit scenes.';

  @override
  String get colorizeIntensityLabel => 'Intensity';

  @override
  String get colorizeRemoveButton => 'Remove colorization';

  @override
  String get colorizeFailedMessage =>
      'Colorize couldn\'t run on this photo. It\'s been turned back off.';

  @override
  String get colorizeFailedStatus => 'Colorize failed';

  @override
  String get colorizeCpuWarning =>
      'Colorize is running on the CPU (no compatible GPU found) — this will be slower than usual.';

  @override
  String get aiDenoiseLevelOff => 'Off';

  @override
  String get aiDenoiseLevelLight => 'Light';

  @override
  String get aiDenoiseLevelMedium => 'Medium';

  @override
  String get aiDenoiseLevelStrong => 'Strong';

  @override
  String get aiDenoiseApplyButton => 'Apply';

  @override
  String get aiDenoiseApplyingMessage => 'Applying AI Denoise...';

  @override
  String get aiDenoiseDisablingMessage => 'Disabling AI Denoise...';

  @override
  String get colorizeStartingMessage => 'Running Colorize...';

  @override
  String get colorizeApplyingMessage => 'Applying Colorize...';

  @override
  String get colorizeDisablingMessage => 'Disabling Colorize...';

  @override
  String get aiDenoiseTabClassic => 'Classic';

  @override
  String get aiDenoiseTabEnhance => 'Enhance';

  @override
  String get aiDenoiseTabCloud => 'Cloud AI';

  @override
  String get aiDenoiseCloudMessage =>
      'Send this photo to a cloud AI provider you have your own account and API key with. Costs real money per photo and uploads the photo to a third party — the on-device Enhance tab is free and stays on your machine.';

  @override
  String get aiDenoiseCloudProviderLabel => 'Provider';

  @override
  String get aiDenoiseCloudProviderOff => 'Off';

  @override
  String get aiDenoiseCloudProviderTopaz => 'Topaz Labs (Denoise)';

  @override
  String get aiDenoiseCloudProviderOpenAi => 'OpenAI (gpt-image-1)';

  @override
  String get aiDenoiseCloudProviderGemini => 'Google Gemini';

  @override
  String get aiDenoiseCloudTokenLabel => 'API key';

  @override
  String get aiDenoiseCloudTokenHint => 'Paste your API key';

  @override
  String get aiDenoiseCloudDisclosure =>
      'Stored only on this device (Windows Credential Manager), sent only to the selected provider. Each apply uploads the full-resolution photo and is billed by your provider account — results are cached so re-opening or exporting the same photo doesn\'t call it again.';

  @override
  String get aiDenoiseCloudGenerativeWarning =>
      'This provider regenerates the image from a prompt rather than running a dedicated denoise model — it may alter fine detail (faces, text, texture), not just remove noise.';

  @override
  String aiDenoiseCloudFailedMessage(String error) {
    return 'Cloud AI denoise failed: $error';
  }

  @override
  String get aiDenoiseCloudFailedStatus => 'Cloud denoise failed';

  @override
  String get aiDenoiseCloudStartingMessage => 'Starting cloud denoise…';

  @override
  String get aiDenoiseCloudStageUploading => 'Uploading photo…';

  @override
  String get aiDenoiseCloudStageProcessing => 'Processing…';

  @override
  String get aiDenoiseCloudStageDownloading => 'Downloading result…';

  @override
  String get aiDenoiseCloudStageDecoding => 'Decoding photo…';

  @override
  String get aiDenoiseEnhanceMessage =>
      'Denoise, remove film grain, and double the resolution using a neural network — closer to what the shot\'s real detail looked like before noise and compression. Runs noticeably slower than Classic, especially without a compatible GPU.';

  @override
  String get aiDenoiseEnhanceDenoiseLabel => 'Denoise';

  @override
  String get aiDenoiseEnhanceAmountLabel => 'Amount';

  @override
  String get aiDenoiseEnhanceRestoreDetailLabel => 'Restore detail';

  @override
  String get aiDenoiseEnhanceUpscaleLabel => 'Upscale 2x';

  @override
  String get aiDenoiseEnhanceSharpnessLabel => 'Sharpness';

  @override
  String get aiDenoiseEnhanceSharpnessCaption =>
      'Blends in a slower, more detail-synthesizing model — any amount above 0% costs ~3.5 minutes per 24MP photo instead of a few seconds, and can slightly alter (not just sharpen) very small text or detail.';

  @override
  String get aiDenoiseEnhanceRawDenoiseLabel => 'RAW denoise (before demosaic)';

  @override
  String get aiDenoiseEnhanceRawDenoiseUnavailableCaption =>
      'Only available for standard Bayer RAW files (not X-Trans, Foveon, or non-RAW formats).';

  @override
  String get aiDenoiseEnhanceFailedMessage =>
      'AI Enhance couldn\'t run on this photo. It\'s been turned back off.';

  @override
  String aiDenoiseCustomModelFallbackMessage(String error) {
    return 'Your custom denoise model couldn\'t be used ($error) — used the default model instead.';
  }

  @override
  String get aiDenoiseCustomModelFallbackStatus =>
      'Custom model failed, used default';

  @override
  String get aiDenoiseEnhanceCpuWarning =>
      'Your GPU doesn\'t support this yet, so it\'s running on the CPU instead — this will take noticeably longer.';

  @override
  String get aiDenoiseEnhanceGpuIncompatibleWarning =>
      'Your GPU isn\'t compatible with this yet, so it\'ll run on the CPU — expect this to take noticeably longer (up to a couple of minutes on a large photo).';

  @override
  String get aiDenoiseEnhanceStartingMessage => 'Running AI Enhance...';

  @override
  String get aiDenoiseEnhanceStageDenoise => 'Denoising';

  @override
  String get aiDenoiseEnhanceStageUpscale => 'Upscaling';

  @override
  String get aiDenoiseEnhanceStageRawDenoise => 'Denoising (RAW)';

  @override
  String get aiDenoiseEnhanceStageDetailRestore => 'Restoring detail';

  @override
  String get aiDenoiseEnhanceStageDetailSharpen => 'Sharpening detail';

  @override
  String get aiDenoiseEnhanceStageSharpen => 'Sharpening';

  @override
  String get aiDenoiseEnhanceStageColorize => 'Colorizing';

  @override
  String aiDenoiseEnhanceTileProgress(String stage, int percent) {
    return '$stage — $percent%';
  }

  @override
  String get exportPanelButton => 'Export';

  @override
  String get exportingButton => 'Exporting...';

  @override
  String get exportStageDecoding => 'Decoding RAW...';

  @override
  String get exportStageRendering => 'Applying edits...';

  @override
  String get exportStageEncoding => 'Encoding...';

  @override
  String get exportStageWriting => 'Saving file...';

  @override
  String get photoStageOpening => 'Opening file...';

  @override
  String get photoStageUnpacking => 'Reading sensor data...';

  @override
  String get photoStageProcessing => 'Developing...';

  @override
  String get photoStageExtracting => 'Preparing image...';

  @override
  String get exportPhotoDialogTitle => 'Export Photo';

  @override
  String get exportRapidLabel => 'Rapid export';

  @override
  String get exportRapidHint => 'Compressed JPEG for social media';

  @override
  String get exportRapidScaleLabel => 'Resolution';

  @override
  String exportRapidScaleResultLabel(int width, int height) {
    return '≈ $width × $height px';
  }

  @override
  String get exportFormatLabel => 'Format';

  @override
  String get exportQualityLabel => 'Quality';

  @override
  String get exportDialogConfirm => 'Export';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get copyButton => 'Copy';

  @override
  String get hideButton => 'Hide';

  @override
  String exportSuccessMessage(String path) {
    return 'Exported to $path';
  }

  @override
  String get exportDoneStatus => 'Done!';

  @override
  String get exportFailedStatus => 'Export failed';

  @override
  String get aiDenoiseEnhanceFailedStatus => 'AI Enhance failed';

  @override
  String exportFailureMessage(String error) {
    return 'Export failed: $error';
  }

  @override
  String get resetTooltip => 'Reset';

  @override
  String get settingsDialogTitle => 'Settings';

  @override
  String get settingsTabGeneral => 'General';

  @override
  String get settingsTabPerformance => 'Performance';

  @override
  String get settingsTabData => 'Data';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageAuto => 'Automatic (system)';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguagePortuguese => 'Portuguese';

  @override
  String get settingsLanguageGerman => 'German';

  @override
  String get settingsFastPreviewLabel => 'Fast preview while dragging sliders';

  @override
  String get settingsPreviewResolutionLabel => 'Preview resolution';

  @override
  String get settingsPreviewResolutionNative => 'Native';

  @override
  String get settingsPreviewResolutionHint =>
      'Lower is faster to open and edit photos; export always uses the full sensor resolution';

  @override
  String get settingsEditEmbeddedJpegLabel => 'Edit the camera\'s JPEG';

  @override
  String get settingsEditEmbeddedJpegHint =>
      'Edit a RAW as the camera\'s own JPEG rendering rather than as sensor data. It opens faster and starts from the look the camera intended, but a rendered 8-bit image has far less latitude to recover a blown sky or a crushed shadow.';

  @override
  String get settingsCacheStorageLabel => 'Cache storage';

  @override
  String get settingsCacheMeasuring => 'Measuring...';

  @override
  String settingsCacheUsedOf(String used, String limit) {
    return '$used of $limit';
  }

  @override
  String get settingsCachePreviews => 'Previews';

  @override
  String get settingsCacheFullSources => 'Full-resolution sources';

  @override
  String get settingsCacheThumbnails => 'Thumbnails';

  @override
  String get settingsCacheAiResults => 'AI results';

  @override
  String get settingsCacheLimitLabel => 'Cache limit';

  @override
  String get settingsCacheLimitUnlimited => 'No limit';

  @override
  String get settingsCacheLimitHint =>
      'Previews and full-resolution sources are deleted oldest-first to stay under this. AI results are never deleted automatically — they cost minutes of processing to rebuild, not seconds.';

  @override
  String settingsClearCacheTooltip(String category) {
    return 'Clear $category';
  }

  @override
  String get settingsClearAllCachesButton => 'Clear all caches';

  @override
  String confirmClearCacheMessage(String category) {
    return 'Delete every cached $category? They are rebuilt as photos are opened again.';
  }

  @override
  String get confirmClearAiCacheMessage =>
      'Delete every cached AI result? These took minutes of processing each and running them again costs that time over, not a quick re-decode.';

  @override
  String get confirmClearAllCachesMessage =>
      'Delete every cache, including AI results? Previews and thumbnails come back on their own; AI results have to be run again, which takes minutes per photo.';

  @override
  String get settingsRawOnlyLabel => 'RAW files only';

  @override
  String get settingsIncludeSubfoldersLabel => 'Subfolder images';

  @override
  String get settingsRawOnlyHint =>
      'Hide JPEG, PNG and other common image formats from the library';

  @override
  String get settingsAnimationsLabel => 'Interface animations';

  @override
  String get settingsAnimationsHint =>
      'Smooth transitions for panel sections, tab switches, zoom, and the preview after an edit';

  @override
  String get settingsGpuRenderLabel => 'Use GPU rendering';

  @override
  String get settingsGpuRenderHint =>
      'Renders on the graphics card instead of the CPU; falls back automatically if unsupported';

  @override
  String get settingsXmpSidecarLabel => 'Write XMP sidecar files';

  @override
  String get settingsXmpSidecarHint =>
      'Saves each photo\'s edits in a .xmp file next to it, so they follow the photo when it moves and can be read by other editors';

  @override
  String get settingsThumbnailThreadsLabel => 'Thumbnail loading threads';

  @override
  String get settingsCustomDenoiseModelLabel => 'Custom denoise model';

  @override
  String get settingsCustomDenoiseModelHint =>
      'Replaces the on-device Denoise model in the AI Denoise dialog\'s Enhance tab. Must be a drop-in replacement: 3-channel RGB, same-resolution in/out, [0,1]-normalized (tensor names are read from the model, so any naming works) — a model that doesn\'t match will error or produce visibly wrong output, not a clean failure.';

  @override
  String get settingsCustomDenoiseModelDefault => 'Default (RealPLKSR)';

  @override
  String get settingsCustomDenoiseModelPickerTitle =>
      'Choose a denoise model (.onnx)';

  @override
  String get settingsCustomDenoiseModelChooseButton => 'Choose file…';

  @override
  String get settingsCustomDenoiseModelResetButton => 'Reset';

  @override
  String get settingsClearThumbnailsButton => 'Clear thumbnail cache';

  @override
  String get settingsClearRecentFilesButton => 'Clear recent files list';

  @override
  String get settingsClearCatalogButton => 'Clear catalog (all edits)';

  @override
  String get settingsPruneMissingButton => 'Remove missing photos from catalog';

  @override
  String get settingsDevLoggingLabel => 'Developer mode';

  @override
  String get settingsDevLoggingHint =>
      'Writes a detailed log to disk (errors, AI Enhance GPU/CPU status, etc.) for bug reports. Off by default.';

  @override
  String get settingsOpenLogFolderButton => 'Open log folder';

  @override
  String get confirmClearTitle => 'Clear data?';

  @override
  String get confirmClearThumbnailsMessage =>
      'This deletes every cached thumbnail. They\'ll be regenerated next time you open a folder.';

  @override
  String get confirmClearRecentFilesMessage =>
      'This clears your recent files list. Folders you\'ve added stay untouched.';

  @override
  String get confirmClearCatalogMessage =>
      'This permanently deletes every saved edit for every photo. This can\'t be undone.';

  @override
  String get confirmPruneMissingMessage =>
      'This removes saved edits, curves, masks, presets, and recent-file entries for photos that no longer exist on disk. This can\'t be undone.';

  @override
  String pruneMissingResultMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Removed $count missing photos from the catalog',
      one: 'Removed 1 missing photo from the catalog',
      zero: 'No missing photos found',
    );
    return '$_temp0';
  }

  @override
  String get clearButton => 'Clear';

  @override
  String get closeButton => 'Close';

  @override
  String get filmstripResetEditsAction => 'Reset all edits';

  @override
  String get filmstripShowOnDiskAction => 'Show on disk';

  @override
  String get filmstripDeleteAction => 'Delete';

  @override
  String get filmstripRatingLabel => 'Rating';

  @override
  String get filmstripColorLabel => 'Color label';

  @override
  String get labelNone => 'None';

  @override
  String get labelRed => 'Red';

  @override
  String get labelYellow => 'Yellow';

  @override
  String get labelGreen => 'Green';

  @override
  String get labelBlue => 'Blue';

  @override
  String get labelPurple => 'Purple';

  @override
  String get imageContextCopyEditsAction => 'Copy Edits';

  @override
  String get imageContextPasteEditsAction => 'Paste Edits';

  @override
  String get filmstripResetEditsConfirmTitle => 'Reset all edits?';

  @override
  String filmstripResetEditsConfirmMessage(String name) {
    return 'This resets \"$name\" back to its untouched state — every adjustment, curve, and mask. This can\'t be undone.';
  }

  @override
  String get filmstripDeleteConfirmTitle => 'Delete photo?';

  @override
  String filmstripDeleteConfirmMessage(String name) {
    return 'This sends \"$name\" to the Recycle Bin and deletes its saved edits. You can restore the photo from the Recycle Bin, but not its edits.';
  }

  @override
  String filmstripDeleteFailedMessage(String name, String error) {
    return 'Couldn\'t delete \"$name\": $error';
  }

  @override
  String get sectionColorProfile => 'COLOR PROFILE';

  @override
  String get sectionWhiteBalance => 'WHITE BALANCE';

  @override
  String get sectionTone => 'TONE';

  @override
  String get sectionPresence => 'PRESENCE';

  @override
  String get sectionDetail => 'DETAIL';

  @override
  String get sectionToneCurve => 'TONE CURVE';

  @override
  String get sectionColorCurve => 'COLOR CURVE';

  @override
  String get sectionColorMixer => 'COLOR MIXER';

  @override
  String get sectionColorGrading => 'COLOR GRADING';

  @override
  String get sectionEffects => 'EFFECTS';

  @override
  String get gradeRangeMidtones => 'Midtones';

  @override
  String get gradeRangeGlobal => 'Global';

  @override
  String get maskImageLayer => 'Full Image';

  @override
  String get maskLinearGradient => 'Linear Gradient';

  @override
  String get maskRadialGradient => 'Radial Gradient';

  @override
  String get maskBrush => 'Brush';

  @override
  String get maskAddTooltip => 'Add mask';

  @override
  String get maskEnabledLabel => 'Enabled';

  @override
  String get maskInvertLabel => 'Invert';

  @override
  String get maskOpacityLabel => 'Opacity';

  @override
  String get maskCloneTooltip => 'Duplicate mask';

  @override
  String get maskCloneSuffix => 'copy';

  @override
  String get maskOkButton => 'OK';

  @override
  String get maskDeleteTooltip => 'Delete mask';

  @override
  String get maskResetTooltip => 'Reset this mask';

  @override
  String get maskClearAllTooltip => 'Clear all masks';

  @override
  String get maskOverlayVisibleTooltip => 'Hide mask overlay';

  @override
  String get maskOverlayHiddenTooltip => 'Show mask overlay';

  @override
  String get maskDisableTooltip => 'Disable mask';

  @override
  String get maskEnableTooltip => 'Enable mask';

  @override
  String get masksTitle => 'Masks';

  @override
  String get histogramTitle => 'Histogram';

  @override
  String histogramShadowClipping(String percent) {
    return 'Shadows clipped: $percent% of the frame';
  }

  @override
  String histogramHighlightClipping(String percent) {
    return 'Highlights clipped: $percent% of the frame';
  }

  @override
  String get histogramNoShadowClipping => 'No shadow clipping';

  @override
  String get histogramNoHighlightClipping => 'No highlight clipping';

  @override
  String get filmstripEditedTooltip => 'Edited';

  @override
  String get maskBrushSizeLabel => 'Brush Size';

  @override
  String get maskBrushHardnessLabel => 'Hardness';

  @override
  String get maskBrushEraseLabel => 'Erase';

  @override
  String get maskUndoStrokeTooltip => 'Undo last stroke';

  @override
  String get maskColorRange => 'Color Range';

  @override
  String get colorRangeToleranceLabel => 'Tolerance';

  @override
  String get colorRangeFeatherLabel => 'Feather';

  @override
  String get colorRangeHint => 'Tap the image to pick a color';

  @override
  String get maskWholeImage => 'Whole Image';

  @override
  String get maskLuminance => 'Luminance Range';

  @override
  String get maskFlow => 'Flow';

  @override
  String get luminanceToleranceLabel => 'Tolerance';

  @override
  String get luminanceFeatherLabel => 'Feather';

  @override
  String get maskSubject => 'Subject';

  @override
  String get maskSky => 'Sky';

  @override
  String get maskForeground => 'Foreground';

  @override
  String get maskDepth => 'Depth';

  @override
  String get subjectMaskHint => 'Drag a box around the subject, or tap it';

  @override
  String get depthNearLabel => 'Near';

  @override
  String get depthFarLabel => 'Far';

  @override
  String get depthFeatherLabel => 'Feather';

  @override
  String get aiMaskComputing => 'Detecting…';

  @override
  String get aiMaskFailed => 'Detection failed';

  @override
  String get luminanceHint => 'Tap the image to pick a brightness';

  @override
  String get flowAmountLabel => 'Flow';

  @override
  String get colorChannelRed => 'Red';

  @override
  String get colorChannelOrange => 'Orange';

  @override
  String get colorChannelYellow => 'Yellow';

  @override
  String get colorChannelGreen => 'Green';

  @override
  String get colorChannelAqua => 'Aqua';

  @override
  String get colorChannelBlue => 'Blue';

  @override
  String get colorChannelPurple => 'Purple';

  @override
  String get colorChannelMagenta => 'Magenta';

  @override
  String get mixerHueLabel => 'Hue';

  @override
  String get mixerSaturationLabel => 'Saturation';

  @override
  String get mixerLuminanceLabel => 'Luminance';

  @override
  String get mixerModeMixerLabel => 'Mixer';

  @override
  String get mixerModeHslLabel => 'HSL';

  @override
  String get sliderTemperature => 'Temperature';

  @override
  String get sliderTint => 'Tint';

  @override
  String get wbModeAsShot => 'As Shot';

  @override
  String get wbModeAuto => 'Auto';

  @override
  String get wbModeDaylight => 'Daylight';

  @override
  String get wbModeCloudy => 'Cloudy';

  @override
  String get wbModeShade => 'Shade';

  @override
  String get wbModeTungsten => 'Tungsten';

  @override
  String get wbModeFluorescent => 'Fluorescent';

  @override
  String get wbModeFlash => 'Flash';

  @override
  String get wbModeCustom => 'Custom';

  @override
  String get wbEyedropperTooltip => 'Pick a neutral gray to set white balance';

  @override
  String get sliderExposure => 'Exposure';

  @override
  String get sliderBrightness => 'Brightness';

  @override
  String get sliderContrast => 'Contrast';

  @override
  String get sliderHighlights => 'Highlights';

  @override
  String get sliderShadows => 'Shadows';

  @override
  String get sliderWhites => 'Whites';

  @override
  String get sliderBlacks => 'Blacks';

  @override
  String get sliderColorProfileAmount => 'Color Profile Contrast';

  @override
  String get colorProfileModeDefault => 'Default';

  @override
  String get colorProfileModeFlat => 'Vivid';

  @override
  String get colorProfileModeMissing => 'Custom profile (not installed)';

  @override
  String get colorProfileMissingWarning =>
      'This photo uses a custom colour profile that is not installed. Rendering with Default until it is imported — the photo still remembers which profile it wants.';

  @override
  String get sliderTexture => 'Texture';

  @override
  String get sliderClarity => 'Clarity';

  @override
  String get sliderDehaze => 'Dehaze';

  @override
  String get sliderVibrance => 'Vibrance';

  @override
  String get sliderSaturation => 'Saturation';

  @override
  String get sliderSharpenAmount => 'Sharpening';

  @override
  String get sliderSharpenRadius => 'Radius';

  @override
  String get sliderSharpenDetail => 'Detail';

  @override
  String get sliderSharpenMasking => 'Masking';

  @override
  String get sliderVignetteAmount => 'Vignette Amount';

  @override
  String get sliderVignetteMidpoint => 'Vignette Midpoint';

  @override
  String get sliderVignetteFeather => 'Vignette Feather';

  @override
  String get sliderGrainAmount => 'Grain Amount';

  @override
  String get sliderGrainSize => 'Grain Size';

  @override
  String get sliderGrainRoughness => 'Grain Roughness';

  @override
  String get sliderParamCurveShadows => 'Shadows';

  @override
  String get sliderParamCurveDarks => 'Darks';

  @override
  String get sliderParamCurveLights => 'Lights';

  @override
  String get sliderParamCurveHighlights => 'Highlights';

  @override
  String get sliderParamCurveShadowSplit => 'Shadow Split';

  @override
  String get sliderParamCurveMidtoneSplit => 'Midtone Split';

  @override
  String get sliderParamCurveHighlightSplit => 'Highlight Split';

  @override
  String get toneCurveParametricLabel => 'Parametric';

  @override
  String get sectionLensCorrection => 'LENS CORRECTION';

  @override
  String get lensCorrectionNoProfileFound => 'No profile found';

  @override
  String get lensCorrectionProfileLabel => 'Lens Profile';

  @override
  String get lensCorrectionAutoDetect => 'Auto-detect';

  @override
  String get lensCorrectionDistortionLabel => 'Distortion';

  @override
  String get lensCorrectionVignetteLabel => 'Vignetting';

  @override
  String get lensCorrectionChromaticAberrationLabel => 'Chromatic Aberration';

  @override
  String get lensCorrectionSearchHint => 'Search lenses…';

  @override
  String get lensCorrectionSearchNoMatches => 'No matches';

  @override
  String get colorProfileEditorTitleNew => 'New colour profile';

  @override
  String get colorProfileEditorTitleEdit => 'Edit colour profile';

  @override
  String get colorProfileEditorTabTone => 'Tone';

  @override
  String get colorProfileEditorTabColor => 'Colour';

  @override
  String get colorProfileEditorTabBase => 'Base';

  @override
  String get colorProfileEditorToneHint =>
      'Remaps brightness while keeping colour. Drag a point to reshape, click empty space to add one, right-click to remove.';

  @override
  String get colorProfileEditorPhotoSlidersHint =>
      'These two apply to the open photo, not to the profile — they are here because a curve only means something once you see how hard it is applied.';

  @override
  String get colorProfileEditorBasicHint =>
      'Eight hue ranges. Each covers three of the profile\'s 24 bins.';

  @override
  String get colorProfileEditorAdvancedHint =>
      'All 24 hue bins, one every 15 degrees.';

  @override
  String get colorProfileEditorModeBasic => 'Basic';

  @override
  String get colorProfileEditorModeAdvanced => 'Advanced';

  @override
  String get colorProfileEditorHue => 'Hue';

  @override
  String get colorProfileEditorSaturation => 'Saturation';

  @override
  String get colorProfileEditorLuminance => 'Luminance';

  @override
  String get colorProfileEditorNameLabel => 'Profile name';

  @override
  String get colorProfileEditorNameTaken =>
      'A profile with this name already exists. Saving will add a number to keep them apart.';

  @override
  String get colorProfileEditorResetHint =>
      'Clears the tone curve and every hue adjustment. The name is kept.';

  @override
  String get colorProfileEditorReset => 'Reset everything';

  @override
  String get colorProfileNewTooltip => 'Create a colour profile';

  @override
  String get hueRangeRed => 'Red';

  @override
  String get hueRangeOrange => 'Orange';

  @override
  String get hueRangeYellow => 'Yellow';

  @override
  String get hueRangeGreen => 'Green';

  @override
  String get hueRangeAqua => 'Aqua';

  @override
  String get hueRangeBlue => 'Blue';

  @override
  String get hueRangePurple => 'Purple';

  @override
  String get hueRangeMagenta => 'Magenta';

  @override
  String get colorProfileRenameTitle => 'Rename colour profile';

  @override
  String get colorProfileExportDialogTitle => 'Export colour profile';

  @override
  String get colorProfileImportDialogTitle => 'Import colour profile';

  @override
  String get colorProfileImportFailed =>
      'That file could not be read as a colour profile.';

  @override
  String get colorProfileDeleteTitle => 'Delete colour profile';

  @override
  String colorProfileDeleteMessage(String name) {
    return 'Delete \"$name\"? Photos already using it will fall back to Default and say so, and will use it again if you import it back.';
  }

  @override
  String get colorProfileMenuTooltip => 'Colour profile actions';

  @override
  String get colorProfileEditLabel => 'Edit';

  @override
  String get colorProfileDuplicateLabel => 'Duplicate';

  @override
  String get colorProfileImportLabel => 'Import...';

  @override
  String get colorProfileEyedropper => 'Pick a colour from the photo';

  @override
  String get controlsTabAdjust => 'Adjust';

  @override
  String get controlsTabColour => 'Colour';

  @override
  String get controlsTabEffects => 'Effects';

  @override
  String get settingsPanelLayoutLabel => 'Editing panel';

  @override
  String get settingsPanelLayoutTabbed => 'Tabs';

  @override
  String get settingsPanelLayoutFlat => 'One long list';

  @override
  String get settingsTabStyleLabel => 'Tab labels';

  @override
  String get settingsTabStyleText => 'Text';

  @override
  String get settingsTabStyleIcons => 'Icons';

  @override
  String get settingsPresetThumbnailsLabel => 'Preset previews';

  @override
  String get settingsPresetThumbnailsHint =>
      'Show each preset applied to the current photo';

  @override
  String get settingsPanelLayoutHint =>
      'Tabs group the sections into Adjust, Colour and Effects. Masks stay pinned above them either way.';

  @override
  String get controlsTabDetails => 'Details';

  @override
  String get transformLevelButton => 'Level';

  @override
  String get transformLevelNothingFound =>
      'Nothing straight enough to level by. Straighten by hand.';

  @override
  String get transformAutoButton => 'Auto';

  @override
  String get transformAutoTooltip =>
      'Level the photo and correct converging verticals';

  @override
  String get transformVerticalButton => 'Vertical';

  @override
  String get transformVerticalTooltip =>
      'Level and correct converging verticals, even on faint evidence';

  @override
  String get transformFullButton => 'Full';

  @override
  String get transformFullTooltip =>
      'Also correct converging horizontals — for architecture, since it will skew a landscape';

  @override
  String get transformAutoNothingFound =>
      'Nothing straight enough to correct by. Adjust by hand.';
}
