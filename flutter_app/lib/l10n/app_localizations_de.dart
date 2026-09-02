// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get menuFile => 'Datei';

  @override
  String get menuOpenFile => 'Datei öffnen';

  @override
  String get menuOpenFolder => 'Ordner hinzufügen';

  @override
  String get menuSettings => 'Einstellungen';

  @override
  String get menuAbout => 'Über';

  @override
  String get aboutDialogTitle => 'Über darkmoon';

  @override
  String get aboutCredits => 'Entwickelt von Vini';

  @override
  String get splashLicense => 'GNU Affero General Public License v3.0';

  @override
  String get splashCopyright => '© 2026 Vini. Lizenziert unter GNU AGPL v3.0.';

  @override
  String get splashLoading => 'Bibliothek wird geladen…';

  @override
  String get dialogOpenFolderTitle => 'Ordner hinzufügen';

  @override
  String get dialogOpenFileTitle => 'RAW-Datei öffnen';

  @override
  String get loadingFolder => 'Ordner wird geladen...';

  @override
  String loadingPhotos(int loaded, int total) {
    return 'Fotos werden geladen... ($loaded/$total)';
  }

  @override
  String loadingImage(String name) {
    return '$name wird geladen...';
  }

  @override
  String get applyingAdjustments => 'Anpassungen werden angewendet...';

  @override
  String get emptyStateOpenFolder =>
      'Öffne einen Ordner mit RAW-Dateien, um zu beginnen';

  @override
  String get noFolderOpen => 'Kein Ordner geöffnet';

  @override
  String decodingPhoto(String name) {
    return '$name\n(wird dekodiert...)';
  }

  @override
  String photoNotFoundMessage(String name) {
    return '$name\nwurde nicht gefunden — die Datei wurde möglicherweise außerhalb von darkmoon verschoben, umbenannt oder gelöscht';
  }

  @override
  String get sidebarRecentFilesSection => 'ZULETZT VERWENDET';

  @override
  String get sidebarFoldersSection => 'ORDNER';

  @override
  String get sidebarRemoveFolderTooltip => 'Ordner entfernen';

  @override
  String get sidebarRemoveRecentFileTooltip =>
      'Aus zuletzt verwendeten Dateien entfernen';

  @override
  String get sidebarFolderNotFoundTooltip =>
      'Ordner nicht gefunden — aus der Liste entfernen';

  @override
  String get sidebarPresetsSection => 'VORGABEN';

  @override
  String get presetImportTooltip => 'Vorgaben importieren (.xmp oder .zip)';

  @override
  String get presetSaveNewTooltip =>
      'Aktuelle Bearbeitung als Vorgabe speichern';

  @override
  String get presetEmptyHint => 'Noch keine Vorgaben';

  @override
  String presetAmountDialogTitle(String name) {
    return '\"$name\" anwenden';
  }

  @override
  String get presetAmountLabel => 'Farbprofil-Stärke';

  @override
  String get presetAmountApplyButton => 'Anwenden';

  @override
  String get presetRenameLabel => 'Umbenennen';

  @override
  String get presetExportLabel => 'Exportieren';

  @override
  String get presetDeleteLabel => 'Löschen';

  @override
  String get presetSaveLabel => 'Speichern';

  @override
  String get presetSaveNewTitle => 'Vorgabe speichern';

  @override
  String get presetRenameTitle => 'Vorgabe umbenennen';

  @override
  String get presetExportDialogTitle => 'Vorgabe exportieren';

  @override
  String get presetExportManyTooltip => 'Auswahl als .zip exportieren';

  @override
  String get presetExportManyDialogTitle => 'Vorgaben exportieren';

  @override
  String get presetImportDialogTitle => 'Vorgaben importieren';

  @override
  String presetDeleteConfirmMessage(String name) {
    return 'Vorgabe \"$name\" löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String presetDeleteManyConfirmMessage(int count) {
    return '$count Vorgaben löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get presetSelectTooltip => 'Vorgaben auswählen';

  @override
  String get presetSelectAllTooltip => 'Alle auswählen';

  @override
  String presetSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get beforeLabel => 'Vorher';

  @override
  String get afterLabel => 'Nachher';

  @override
  String get zoomFit => 'Einpassen';

  @override
  String get fitToWindow => 'An Fenster anpassen';

  @override
  String get beforeAfterButton => 'Vorher/Nachher';

  @override
  String get cropButton => 'Zuschneiden & Transformieren';

  @override
  String get sectionCropTransform => 'ZUSCHNEIDEN & TRANSFORMIEREN';

  @override
  String get cropAspectLabel => 'Seitenverhältnis';

  @override
  String get transformStraightenLabel => 'Begradigen';

  @override
  String get transformVerticalLabel => 'Vertikal';

  @override
  String get transformHorizontalLabel => 'Horizontal';

  @override
  String get transformAspectLabel => 'Seitenverhältnis';

  @override
  String get transformScaleLabel => 'Skalierung';

  @override
  String get cropRotateLeftTooltip => '90° nach links drehen';

  @override
  String get cropRotateRightTooltip => '90° nach rechts drehen';

  @override
  String get cropDoneButton => 'OK';

  @override
  String get undoButton => 'Rückgängig';

  @override
  String get redoButton => 'Wiederholen';

  @override
  String get aiDenoiseButton => 'KI-Rauschunterdrückung';

  @override
  String get aiDenoiseDialogTitle => 'KI-Rauschunterdrückung';

  @override
  String get aiDenoiseDialogMessage =>
      'Reduziert Bildrauschen automatisch, ohne Details zu verlieren.';

  @override
  String get colorizeButton => 'Kolorieren';

  @override
  String get colorizeDialogTitle => 'Kolorieren';

  @override
  String get colorizeDialogMessage =>
      'Fügt einem Schwarzweiß- oder verblassten Foto mithilfe von KI Farbe hinzu. Funktioniert am besten bei echten Tageslichtfotos — kann bei Nachtaufnahmen oder Kunstlicht seltsam wirken.';

  @override
  String get colorizeIntensityLabel => 'Intensität';

  @override
  String get colorizeRemoveButton => 'Kolorierung entfernen';

  @override
  String get colorizeFailedMessage =>
      'Kolorieren konnte für dieses Foto nicht ausgeführt werden. Die Option wurde wieder deaktiviert.';

  @override
  String get colorizeFailedStatus => 'Kolorieren fehlgeschlagen';

  @override
  String get colorizeCpuWarning =>
      'Kolorierung läuft auf der CPU (keine kompatible GPU gefunden) — das wird langsamer als gewöhnlich sein.';

  @override
  String get aiDenoiseLevelOff => 'Aus';

  @override
  String get aiDenoiseLevelLight => 'Leicht';

  @override
  String get aiDenoiseLevelMedium => 'Mittel';

  @override
  String get aiDenoiseLevelStrong => 'Stark';

  @override
  String get aiDenoiseApplyButton => 'Anwenden';

  @override
  String get aiDenoiseApplyingMessage =>
      'KI-Rauschunterdrückung wird angewendet...';

  @override
  String get aiDenoiseDisablingMessage =>
      'KI-Rauschunterdrückung wird deaktiviert...';

  @override
  String get colorizeStartingMessage => 'Kolorierung wird ausgeführt...';

  @override
  String get colorizeApplyingMessage => 'Kolorierung wird angewendet...';

  @override
  String get colorizeDisablingMessage => 'Kolorierung wird entfernt...';

  @override
  String get aiDenoiseTabClassic => 'Klassisch';

  @override
  String get aiDenoiseTabEnhance => 'Enhance';

  @override
  String get aiDenoiseTabCloud => 'Cloud-KI';

  @override
  String get aiDenoiseCloudMessage =>
      'Sendet dieses Foto an einen Cloud-KI-Anbieter, bei dem du ein eigenes Konto und einen API-Schlüssel hast. Kostet echtes Geld pro Foto und lädt das Foto zu einem Drittanbieter hoch — der Enhance-Tab ist kostenlos und läuft nur auf deinem Gerät.';

  @override
  String get aiDenoiseCloudProviderLabel => 'Anbieter';

  @override
  String get aiDenoiseCloudProviderOff => 'Aus';

  @override
  String get aiDenoiseCloudProviderTopaz => 'Topaz Labs (Denoise)';

  @override
  String get aiDenoiseCloudProviderOpenAi => 'OpenAI (gpt-image-1)';

  @override
  String get aiDenoiseCloudProviderGemini => 'Google Gemini';

  @override
  String get aiDenoiseCloudTokenLabel => 'API-Schlüssel';

  @override
  String get aiDenoiseCloudTokenHint => 'API-Schlüssel einfügen';

  @override
  String get aiDenoiseCloudDisclosure =>
      'Wird nur auf diesem Gerät gespeichert (Windows-Anmeldeinformationsverwaltung) und nur an den gewählten Anbieter gesendet. Jede Anwendung lädt das Foto in voller Auflösung hoch und wird über dein Anbieterkonto abgerechnet — Ergebnisse werden zwischengespeichert, damit erneutes Öffnen oder Exportieren desselben Fotos keinen erneuten Aufruf auslöst.';

  @override
  String get aiDenoiseCloudGenerativeWarning =>
      'Dieser Anbieter erzeugt das Bild anhand eines Prompts neu, statt ein dediziertes Entrauschungsmodell zu verwenden — feine Details (Gesichter, Text, Textur) können sich dabei verändern, nicht nur das Rauschen wird entfernt.';

  @override
  String aiDenoiseCloudFailedMessage(String error) {
    return 'Cloud-KI-Entrauschung fehlgeschlagen: $error';
  }

  @override
  String get aiDenoiseCloudFailedStatus => 'Cloud-Entrauschung fehlgeschlagen';

  @override
  String get aiDenoiseCloudStartingMessage =>
      'Cloud-Entrauschung wird gestartet…';

  @override
  String get aiDenoiseCloudStageUploading => 'Foto wird hochgeladen…';

  @override
  String get aiDenoiseCloudStageProcessing => 'Wird verarbeitet…';

  @override
  String get aiDenoiseCloudStageDownloading => 'Ergebnis wird heruntergeladen…';

  @override
  String get aiDenoiseCloudStageDecoding => 'Foto wird dekodiert…';

  @override
  String get aiDenoiseEnhanceMessage =>
      'Entfernt Rauschen und Filmkorn und verdoppelt die Auflösung mit einem neuronalen Netz — näher an dem, wie die echten Details vor Rauschen und Kompression aussahen. Läuft spürbar langsamer als Klassisch, besonders ohne kompatible GPU.';

  @override
  String get aiDenoiseEnhanceDenoiseLabel => 'Rauschunterdrückung';

  @override
  String get aiDenoiseEnhanceAmountLabel => 'Stärke';

  @override
  String get aiDenoiseEnhanceRestoreDetailLabel => 'Details wiederherstellen';

  @override
  String get aiDenoiseEnhanceUpscaleLabel => '2x hochskalieren';

  @override
  String get aiDenoiseEnhanceSharpnessLabel => 'Schärfe';

  @override
  String get aiDenoiseEnhanceSharpnessCaption =>
      'Mischt ein langsameres Modell ein, das mehr Detail rekonstruiert — jeder Wert über 0% kostet ca. 3,5 Minuten pro 24-MP-Foto statt weniger Sekunden und kann sehr kleinen Text oder Details leicht verändern (nicht nur schärfen).';

  @override
  String get aiDenoiseEnhanceRawDenoiseLabel =>
      'RAW-Entrauschen (vor dem Demosaicing)';

  @override
  String get aiDenoiseEnhanceRawDenoiseUnavailableCaption =>
      'Nur für Standard-Bayer-RAW-Dateien verfügbar (nicht X-Trans, Foveon oder Nicht-RAW-Formate).';

  @override
  String get aiDenoiseEnhanceFailedMessage =>
      'KI-Enhance konnte auf diesem Foto nicht ausgeführt werden. Wurde wieder deaktiviert.';

  @override
  String aiDenoiseCustomModelFallbackMessage(String error) {
    return 'Dein benutzerdefiniertes Entrauschungsmodell konnte nicht verwendet werden ($error) — stattdessen wurde das Standardmodell verwendet.';
  }

  @override
  String get aiDenoiseCustomModelFallbackStatus =>
      'Benutzerdefiniertes Modell fehlgeschlagen, Standard verwendet';

  @override
  String get aiDenoiseEnhanceCpuWarning =>
      'Deine GPU unterstützt das noch nicht, daher läuft es stattdessen auf der CPU — das wird spürbar länger dauern.';

  @override
  String get aiDenoiseEnhanceGpuIncompatibleWarning =>
      'Deine GPU ist damit noch nicht kompatibel, daher läuft es auf der CPU — rechne mit einer spürbar längeren Dauer (bei einem großen Foto bis zu ein paar Minuten).';

  @override
  String get aiDenoiseEnhanceStartingMessage => 'KI-Enhance wird ausgeführt...';

  @override
  String get aiDenoiseEnhanceStageDenoise => 'Rauschunterdrückung';

  @override
  String get aiDenoiseEnhanceStageUpscale => 'Hochskalierung';

  @override
  String get aiDenoiseEnhanceStageRawDenoise => 'Rauschunterdrückung (RAW)';

  @override
  String get aiDenoiseEnhanceStageDetailRestore =>
      'Details werden wiederhergestellt';

  @override
  String get aiDenoiseEnhanceStageDetailSharpen => 'Details werden geschärft';

  @override
  String get aiDenoiseEnhanceStageSharpen => 'Schärfung';

  @override
  String aiDenoiseEnhanceTileProgress(String stage, int percent) {
    return '$stage — $percent%';
  }

  @override
  String get exportPanelButton => 'Exportieren';

  @override
  String get exportingButton => 'Wird exportiert...';

  @override
  String get exportStageDecoding => 'RAW wird dekodiert...';

  @override
  String get exportStageRendering => 'Bearbeitungen werden angewendet...';

  @override
  String get exportStageEncoding => 'Wird kodiert...';

  @override
  String get exportStageWriting => 'Datei wird gespeichert...';

  @override
  String get exportPhotoDialogTitle => 'Foto exportieren';

  @override
  String get exportRapidLabel => 'Schnellexport';

  @override
  String get exportRapidHint => 'Komprimiertes JPEG für soziale Medien';

  @override
  String get exportRapidScaleLabel => 'Auflösung';

  @override
  String exportRapidScaleResultLabel(int width, int height) {
    return '≈ $width × $height px';
  }

  @override
  String get exportFormatLabel => 'Format';

  @override
  String get exportQualityLabel => 'Qualität';

  @override
  String get exportDialogConfirm => 'Exportieren';

  @override
  String get cancelButton => 'Abbrechen';

  @override
  String get copyButton => 'Kopieren';

  @override
  String get hideButton => 'Ausblenden';

  @override
  String exportSuccessMessage(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String get exportDoneStatus => 'Fertig!';

  @override
  String get exportFailedStatus => 'Export fehlgeschlagen';

  @override
  String get aiDenoiseEnhanceFailedStatus => 'KI-Enhance fehlgeschlagen';

  @override
  String exportFailureMessage(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get resetTooltip => 'Zurücksetzen';

  @override
  String get settingsDialogTitle => 'Einstellungen';

  @override
  String get settingsTabGeneral => 'Allgemein';

  @override
  String get settingsTabPerformance => 'Leistung';

  @override
  String get settingsTabData => 'Daten';

  @override
  String get settingsLanguageLabel => 'Sprache';

  @override
  String get settingsLanguageAuto => 'Automatisch (System)';

  @override
  String get settingsLanguageEnglish => 'Englisch';

  @override
  String get settingsLanguagePortuguese => 'Portugiesisch';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsFastPreviewLabel =>
      'Schnelle Vorschau beim Ziehen der Regler';

  @override
  String get settingsPreviewResolutionLabel => 'Vorschauauflösung';

  @override
  String get settingsPreviewResolutionHint =>
      'Niedriger ist schneller beim Öffnen und Bearbeiten von Fotos; der Export verwendet immer die volle Sensorauflösung';

  @override
  String get settingsRawOnlyLabel => 'Nur RAW-Dateien';

  @override
  String get settingsIncludeSubfoldersLabel => 'Bilder in Unterordnern';

  @override
  String get settingsRawOnlyHint =>
      'JPEG, PNG und andere gängige Bildformate aus der Bibliothek ausblenden';

  @override
  String get settingsAnimationsLabel => 'Oberflächenanimationen';

  @override
  String get settingsAnimationsHint =>
      'Sanfte Übergänge für Panelabschnitte, Tab-Wechsel, Zoom und die Vorschau nach einer Bearbeitung';

  @override
  String get settingsGpuRenderLabel => 'GPU-Rendering verwenden';

  @override
  String get settingsGpuRenderHint =>
      'Rendert auf der Grafikkarte statt auf der CPU; fällt bei fehlender Unterstützung automatisch zurück';

  @override
  String get settingsDynamicFullPreviewLabel =>
      'Dynamische Vorschau in voller Auflösung';

  @override
  String get settingsDynamicFullPreviewHint =>
      'Kurz nachdem sich eine Bearbeitung gesetzt hat, wird in der nativen Sensorauflösung neu gerendert, damit eine gezoomte Ansicht schärfer wird. Dekodierte Quellen werden auf der Festplatte zwischengespeichert.';

  @override
  String get settingsFullQualityScaleLabel => 'Vorschauauflösung';

  @override
  String get settingsThumbnailThreadsLabel =>
      'Threads für das Laden von Miniaturansichten';

  @override
  String get settingsCustomDenoiseModelLabel =>
      'Benutzerdefiniertes Entrauschungsmodell';

  @override
  String get settingsCustomDenoiseModelHint =>
      'Ersetzt das On-Device-Denoise-Modell im Enhance-Tab des KI-Entrauschungsdialogs. Muss ein direkter Ersatz sein: 3-Kanal-RGB, gleiche Auflösung bei Ein-/Ausgabe, Tensor-Namen \"input\"/\"output\", [0,1]-normalisiert — ein Modell, das nicht passt, führt zu einem Fehler oder sichtbar falschem Ergebnis, nicht zu einem sauberen Fehlschlag.';

  @override
  String get settingsCustomDenoiseModelDefault => 'Standard (RealPLKSR)';

  @override
  String get settingsCustomDenoiseModelPickerTitle =>
      'Entrauschungsmodell wählen (.onnx)';

  @override
  String get settingsCustomDenoiseModelChooseButton => 'Datei wählen…';

  @override
  String get settingsCustomDenoiseModelResetButton => 'Zurücksetzen';

  @override
  String get settingsClearThumbnailsButton =>
      'Cache für Miniaturansichten leeren';

  @override
  String get settingsClearRecentFilesButton =>
      'Liste zuletzt verwendeter Dateien leeren';

  @override
  String get settingsClearCatalogButton =>
      'Katalog leeren (alle Bearbeitungen)';

  @override
  String get settingsPruneMissingButton =>
      'Fehlende Fotos aus dem Katalog entfernen';

  @override
  String get settingsDevLoggingLabel => 'Entwicklermodus';

  @override
  String get settingsDevLoggingHint =>
      'Schreibt ein detailliertes Protokoll auf die Festplatte (Fehler, GPU/CPU-Status von KI-Enhance usw.) für Fehlerberichte. Standardmäßig deaktiviert.';

  @override
  String get settingsOpenLogFolderButton => 'Protokollordner öffnen';

  @override
  String get confirmClearTitle => 'Daten löschen?';

  @override
  String get confirmClearThumbnailsMessage =>
      'Dadurch werden alle zwischengespeicherten Miniaturansichten gelöscht. Sie werden beim nächsten Öffnen eines Ordners neu erstellt.';

  @override
  String get confirmClearRecentFilesMessage =>
      'Dadurch wird deine Liste zuletzt verwendeter Dateien geleert. Hinzugefügte Ordner bleiben unberührt.';

  @override
  String get confirmClearCatalogMessage =>
      'Dadurch wird jede gespeicherte Bearbeitung für jedes Foto dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get confirmPruneMissingMessage =>
      'Dadurch werden gespeicherte Bearbeitungen, Kurven, Masken, Vorgaben und Einträge zuletzt verwendeter Dateien für Fotos entfernt, die nicht mehr auf der Festplatte vorhanden sind. Dies kann nicht rückgängig gemacht werden.';

  @override
  String pruneMissingResultMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fehlende Fotos aus dem Katalog entfernt',
      one: '1 fehlendes Foto aus dem Katalog entfernt',
      zero: 'Keine fehlenden Fotos gefunden',
    );
    return '$_temp0';
  }

  @override
  String get clearButton => 'Leeren';

  @override
  String get closeButton => 'Schließen';

  @override
  String get filmstripResetEditsAction => 'Alle Bearbeitungen zurücksetzen';

  @override
  String get filmstripShowOnDiskAction => 'Im Explorer anzeigen';

  @override
  String get filmstripDeleteAction => 'Löschen';

  @override
  String get imageContextCopyEditsAction => 'Bearbeitungen kopieren';

  @override
  String get imageContextPasteEditsAction => 'Bearbeitungen einfügen';

  @override
  String get filmstripResetEditsConfirmTitle =>
      'Alle Bearbeitungen zurücksetzen?';

  @override
  String filmstripResetEditsConfirmMessage(String name) {
    return 'Dadurch wird \"$name\" auf den unbearbeiteten Zustand zurückgesetzt — jede Anpassung, Kurve und Maske. Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get filmstripDeleteConfirmTitle => 'Foto löschen?';

  @override
  String filmstripDeleteConfirmMessage(String name) {
    return 'Dadurch wird \"$name\" in den Papierkorb verschoben und die gespeicherten Bearbeitungen werden gelöscht. Du kannst das Foto aus dem Papierkorb wiederherstellen, aber nicht die Bearbeitungen.';
  }

  @override
  String filmstripDeleteFailedMessage(String name, String error) {
    return '\"$name\" konnte nicht gelöscht werden: $error';
  }

  @override
  String get sectionColorProfile => 'FARBPROFIL';

  @override
  String get sectionWhiteBalance => 'WEISSABGLEICH';

  @override
  String get sectionTone => 'TONWERTE';

  @override
  String get sectionPresence => 'PRÄSENZ';

  @override
  String get sectionDetail => 'DETAIL';

  @override
  String get sectionToneCurve => 'GRADATIONSKURVE';

  @override
  String get sectionColorCurve => 'FARBKURVE';

  @override
  String get sectionColorMixer => 'FARBMISCHER';

  @override
  String get sectionColorGrading => 'FARBABSTUFUNG';

  @override
  String get sectionEffects => 'EFFEKTE';

  @override
  String get gradeRangeMidtones => 'Mitteltöne';

  @override
  String get gradeRangeGlobal => 'Global';

  @override
  String get maskImageLayer => 'Ganzes Bild';

  @override
  String get maskLinearGradient => 'Linearer Verlauf';

  @override
  String get maskRadialGradient => 'Radialer Verlauf';

  @override
  String get maskBrush => 'Pinsel';

  @override
  String get maskAddTooltip => 'Maske hinzufügen';

  @override
  String get maskEnabledLabel => 'Aktiviert';

  @override
  String get maskInvertLabel => 'Invertieren';

  @override
  String get maskOpacityLabel => 'Deckkraft';

  @override
  String get maskOverlayOpacityLabel => 'Overlay-Deckkraft';

  @override
  String get maskCloneTooltip => 'Maske duplizieren';

  @override
  String get maskCloneSuffix => 'Kopie';

  @override
  String get maskDeleteTooltip => 'Maske löschen';

  @override
  String get maskResetTooltip => 'Diese Maske zurücksetzen';

  @override
  String get maskClearAllTooltip => 'Alle Masken entfernen';

  @override
  String get maskOverlayVisibleTooltip => 'Masken-Overlay ausblenden';

  @override
  String get maskOverlayHiddenTooltip => 'Masken-Overlay einblenden';

  @override
  String get maskDisableTooltip => 'Maske deaktivieren';

  @override
  String get maskEnableTooltip => 'Maske aktivieren';

  @override
  String get masksTitle => 'Masken';

  @override
  String get histogramTitle => 'Histogramm';

  @override
  String get filmstripEditedTooltip => 'Bearbeitet';

  @override
  String get maskBrushSizeLabel => 'Pinselgröße';

  @override
  String get maskBrushHardnessLabel => 'Härte';

  @override
  String get maskBrushEraseLabel => 'Radieren';

  @override
  String get maskUndoStrokeTooltip => 'Letzten Pinselstrich rückgängig machen';

  @override
  String get maskColorRange => 'Farbbereich';

  @override
  String get colorRangeToleranceLabel => 'Toleranz';

  @override
  String get colorRangeFeatherLabel => 'Weichzeichnen';

  @override
  String get colorRangeHint => 'Auf das Bild tippen, um eine Farbe auszuwählen';

  @override
  String get maskLuminance => 'Leuchtdichtebereich';

  @override
  String get maskFlow => 'Fluss';

  @override
  String get luminanceToleranceLabel => 'Toleranz';

  @override
  String get luminanceFeatherLabel => 'Weichzeichnen';

  @override
  String get luminanceHint =>
      'Auf das Bild tippen, um eine Helligkeit auszuwählen';

  @override
  String get flowAmountLabel => 'Fluss';

  @override
  String get colorChannelRed => 'Rot';

  @override
  String get colorChannelOrange => 'Orange';

  @override
  String get colorChannelYellow => 'Gelb';

  @override
  String get colorChannelGreen => 'Grün';

  @override
  String get colorChannelAqua => 'Aqua';

  @override
  String get colorChannelBlue => 'Blau';

  @override
  String get colorChannelPurple => 'Lila';

  @override
  String get colorChannelMagenta => 'Magenta';

  @override
  String get mixerHueLabel => 'Farbton';

  @override
  String get mixerSaturationLabel => 'Sättigung';

  @override
  String get mixerLuminanceLabel => 'Luminanz';

  @override
  String get mixerModeMixerLabel => 'Mischer';

  @override
  String get mixerModeHslLabel => 'HSL';

  @override
  String get sliderTemperature => 'Temperatur';

  @override
  String get sliderTint => 'Tönung';

  @override
  String get wbModeAsShot => 'Wie aufgenommen';

  @override
  String get wbModeAuto => 'Automatisch';

  @override
  String get wbModeDaylight => 'Tageslicht';

  @override
  String get wbModeCloudy => 'Bewölkt';

  @override
  String get wbModeShade => 'Schatten';

  @override
  String get wbModeTungsten => 'Glühlampe';

  @override
  String get wbModeFluorescent => 'Leuchtstofflampe';

  @override
  String get wbModeFlash => 'Blitz';

  @override
  String get wbModeCustom => 'Benutzerdefiniert';

  @override
  String get wbEyedropperTooltip =>
      'Ein neutrales Grau auswählen, um den Weißabgleich festzulegen';

  @override
  String get sliderExposure => 'Belichtung';

  @override
  String get sliderBrightness => 'Helligkeit';

  @override
  String get sliderContrast => 'Kontrast';

  @override
  String get sliderHighlights => 'Lichter';

  @override
  String get sliderShadows => 'Tiefen';

  @override
  String get sliderWhites => 'Weiß';

  @override
  String get sliderBlacks => 'Schwarz';

  @override
  String get sliderColorProfileAmount => 'Farbprofil-Kontrast';

  @override
  String get colorProfileModeDefault => 'Standard';

  @override
  String get colorProfileModeFlat => 'Lebendig';

  @override
  String get colorProfileModePastel => 'Pastell';

  @override
  String get colorProfileModeNoir => 'Noir';

  @override
  String get sliderTexture => 'Textur';

  @override
  String get sliderClarity => 'Klarheit';

  @override
  String get sliderDehaze => 'Dunst entfernen';

  @override
  String get sliderVibrance => 'Dynamik';

  @override
  String get sliderSaturation => 'Sättigung';

  @override
  String get sliderSharpenAmount => 'Schärfen';

  @override
  String get sliderSharpenRadius => 'Radius';

  @override
  String get sliderSharpenDetail => 'Detail';

  @override
  String get sliderSharpenMasking => 'Maskierung';

  @override
  String get sliderVignetteAmount => 'Vignette-Stärke';

  @override
  String get sliderVignetteMidpoint => 'Vignette-Mittelpunkt';

  @override
  String get sliderVignetteFeather => 'Vignette-Weichzeichnung';

  @override
  String get sliderGrainAmount => 'Korn-Stärke';

  @override
  String get sliderGrainSize => 'Korngröße';

  @override
  String get sliderGrainRoughness => 'Kornrauheit';

  @override
  String get sliderParamCurveShadows => 'Tiefen';

  @override
  String get sliderParamCurveDarks => 'Dunkle Töne';

  @override
  String get sliderParamCurveLights => 'Helle Töne';

  @override
  String get sliderParamCurveHighlights => 'Lichter';

  @override
  String get sliderParamCurveShadowSplit => 'Tiefen-Aufteilung';

  @override
  String get sliderParamCurveMidtoneSplit => 'Mittelton-Aufteilung';

  @override
  String get sliderParamCurveHighlightSplit => 'Lichter-Aufteilung';

  @override
  String get toneCurveParametricLabel => 'Parametrisch';

  @override
  String get sectionLensCorrection => 'OBJEKTIVKORREKTUR';

  @override
  String get lensCorrectionNoProfileFound => 'Kein Profil gefunden';

  @override
  String get lensCorrectionProfileLabel => 'Objektivprofil';

  @override
  String get lensCorrectionAutoDetect => 'Automatisch erkennen';

  @override
  String get lensCorrectionDistortionLabel => 'Verzerrung';

  @override
  String get lensCorrectionVignetteLabel => 'Vignettierung';

  @override
  String get lensCorrectionChromaticAberrationLabel =>
      'Chromatische Aberration';

  @override
  String get lensCorrectionSearchHint => 'Objektive suchen…';

  @override
  String get lensCorrectionSearchNoMatches => 'Keine Treffer';
}
