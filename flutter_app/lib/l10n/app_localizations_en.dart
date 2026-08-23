// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get menuFile => 'File';

  @override
  String get menuOpenFile => 'Open File';

  @override
  String get menuOpenFolder => 'Add Folder';

  @override
  String get menuSettings => 'Settings';

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
  String get sidebarRecentFilesSection => 'RECENT FILES';

  @override
  String get sidebarFoldersSection => 'FOLDERS';

  @override
  String get sidebarRemoveFolderTooltip => 'Remove folder';

  @override
  String get sidebarPresetsSection => 'PRESETS';

  @override
  String get presetImportTooltip => 'Import presets (.xmp or .zip)';

  @override
  String get presetSaveNewTooltip => 'Save current edits as a preset';

  @override
  String get presetEmptyHint => 'No presets yet';

  @override
  String presetAmountDialogTitle(String name) {
    return 'Apply \"$name\"';
  }

  @override
  String get presetAmountLabel => 'Amount';

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
  String get presetUnsupportedTitle => 'Some settings weren\'t applied';

  @override
  String presetUnsupportedMessage(String name) {
    return 'The preset \"$name\" has settings this app doesn\'t support yet, so they were skipped:';
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
  String get exportPhotoDialogTitle => 'Export Photo';

  @override
  String get exportFormatLabel => 'Format';

  @override
  String get exportQualityLabel => 'Quality';

  @override
  String get exportDialogConfirm => 'Export';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get hideButton => 'Hide';

  @override
  String exportSuccessMessage(String path) {
    return 'Exported to $path';
  }

  @override
  String exportFailureMessage(String error) {
    return 'Export failed: $error';
  }

  @override
  String get resetTooltip => 'Reset';

  @override
  String get settingsDialogTitle => 'Settings';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageAuto => 'Automatic (system)';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguagePortuguese => 'Portuguese';

  @override
  String get settingsFastPreviewLabel => 'Fast preview while dragging sliders';

  @override
  String get settingsPreviewResolutionLabel => 'Preview resolution';

  @override
  String get settingsPreviewResolutionHint =>
      'Lower is faster to open and edit photos; export always uses the full sensor resolution';

  @override
  String get settingsRawOnlyLabel => 'RAW files only';

  @override
  String get settingsRawOnlyHint =>
      'Hide JPEG, PNG and other common image formats from the library';

  @override
  String get settingsGpuRenderLabel => 'Use GPU rendering (experimental)';

  @override
  String get settingsGpuRenderHint =>
      'Renders on the graphics card instead of the CPU; falls back automatically if unsupported';

  @override
  String get settingsThumbnailThreadsLabel => 'Thumbnail loading threads';

  @override
  String get settingsUserDataSection => 'USER DATA';

  @override
  String get settingsClearThumbnailsButton => 'Clear thumbnail cache';

  @override
  String get settingsClearRecentFilesButton => 'Clear recent files list';

  @override
  String get settingsClearCatalogButton => 'Clear catalog (all edits)';

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
  String get clearButton => 'Clear';

  @override
  String get closeButton => 'Close';

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
  String get maskOverlayOpacityLabel => 'Overlay Opacity';

  @override
  String get maskCloneTooltip => 'Duplicate mask';

  @override
  String get maskCloneSuffix => 'copy';

  @override
  String get maskDeleteTooltip => 'Delete mask';

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
  String get maskBrushSizeLabel => 'Size';

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
  String get sliderSharpenAmount => 'Amount';

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
}
