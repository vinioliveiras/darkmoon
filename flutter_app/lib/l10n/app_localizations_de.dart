// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get menuOpenFile => 'Datei öffnen';

  @override
  String get menuOpenFolder => 'Albumordner hinzufügen';

  @override
  String get menuSettings => 'Einstellungen';

  @override
  String get menuAbout => 'Über';

  @override
  String get tabAlbums => 'Alben';

  @override
  String get tabEditor => 'Editor';

  @override
  String get libraryDetailsSection => 'DETAILS';

  @override
  String get libraryDetailsEmpty => 'Wähle ein Foto, um seine Details zu sehen';

  @override
  String get libraryTagsLabel => 'Tags';

  @override
  String get libraryNoTags => 'Keine Tags';

  @override
  String libraryHiddenByRawOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Fotos in diesem Album sind ausgeblendet, weil \"Nur RAW-Dateien\" aktiv ist',
      one:
          '1 Foto in diesem Album ist ausgeblendet, weil \"Nur RAW-Dateien\" aktiv ist',
    );
    return '$_temp0';
  }

  @override
  String get libraryShowAllFormats => 'Alle Formate anzeigen';

  @override
  String libraryUnsupportedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Dateien in diesem Album haben Formate, die diese App nicht öffnen kann',
      one:
          '1 Datei in diesem Album hat ein Format, das diese App nicht öffnen kann',
    );
    return '$_temp0';
  }

  @override
  String get sidebarNewAlbumAction => 'Neues Album hier…';

  @override
  String get sidebarDeleteAlbumAction => 'Album löschen…';

  @override
  String get libraryDeleteAlbumConfirmTitle => 'Album löschen?';

  @override
  String libraryDeleteAlbumConfirmMessage(String name) {
    return 'Dadurch werden das Album \"$name\" und alles darin in den Papierkorb verschoben und die gespeicherten Bearbeitungen seiner Fotos gelöscht.';
  }

  @override
  String get libraryBackFolderTooltip => 'Zurück zum vorherigen Album';

  @override
  String get menuLibrary => 'Bibliothek';

  @override
  String get libraryBackTooltip => 'Zurück zum Editor';

  @override
  String get librarySearchHint => 'Dateinamen durchsuchen';

  @override
  String libraryMinRatingTooltip(int stars) {
    return 'Fotos mit mindestens $stars Sternen anzeigen';
  }

  @override
  String get libraryAllLabelsTooltip => 'Alle Markierungen';

  @override
  String libraryPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos',
      one: '1 Foto',
      zero: 'Keine Fotos',
    );
    return '$_temp0';
  }

  @override
  String get libraryEmptyFolders =>
      'Fügen Sie der Bibliothek einen Ordner hinzu, um ihn hier zu durchsuchen';

  @override
  String get libraryAddFolder => 'Ordner hinzufügen';

  @override
  String get libraryEmpty => 'Keine Fotos in diesem Ordner';

  @override
  String get libraryNoMatches => 'Keine Fotos entsprechen den Filtern';

  @override
  String get libraryOpenInEditor => 'Bearbeiten';

  @override
  String get libraryNewAlbumTitle => 'Neues Album';

  @override
  String get libraryNewAlbumTooltip => 'Neues Album in diesem';

  @override
  String get libraryConvertNegativeAction => 'Negativ umkehren…';

  @override
  String get libraryFrameImageAction => 'Bild rahmen…';

  @override
  String libraryFrameImagesAction(int count) {
    return '$count Bilder rahmen…';
  }

  @override
  String get frameDialogTitle => 'Bildrahmen';

  @override
  String get framePreviewHint =>
      'Vorschau des ersten Fotos; die Datei wird in voller Größe mit den Bearbeitungen gerendert.';

  @override
  String get framePreviewUnavailable =>
      'Für dieses Foto gibt es noch keine Vorschau.';

  @override
  String get frameAspectLabel => 'Seitenverhältnis';

  @override
  String get frameAspectOriginal => 'Original';

  @override
  String get frameOrientationLandscape => 'Querformat';

  @override
  String get frameOrientationPortrait => 'Hochformat';

  @override
  String get frameSpacingLabel => 'Abstand';

  @override
  String get frameRadiusLabel => 'Eckenradius';

  @override
  String get frameBackgroundLabel => 'Hintergrund';

  @override
  String get frameBackgroundHexHint => 'Hex, z. B. F4F1EA';

  @override
  String get frameSizeLabel => 'Lange Kante';

  @override
  String get frameSizeOriginal => 'Originalgröße';

  @override
  String frameSizePixels(int pixels) {
    return '$pixels px';
  }

  @override
  String get frameFormatLabel => 'Format';

  @override
  String get frameSaveButton => 'Gerahmt speichern';

  @override
  String frameSaveAllButton(int count) {
    return 'Alle gerahmt speichern ($count)';
  }

  @override
  String frameSavingProgress(int current, int total) {
    return 'Speichern $current/$total…';
  }

  @override
  String frameSavedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gerahmte Bilder',
      one: '1 gerahmtes Bild',
    );
    return '$_temp0 neben den Originalen gespeichert (_Framed).';
  }

  @override
  String frameFailedMessage(String name) {
    return '$name konnte nicht gerahmt werden.';
  }

  @override
  String libraryConvertNegativesAction(int count) {
    return '$count Negative umkehren…';
  }

  @override
  String get negativeDialogTitle => 'Negativumkehrung';

  @override
  String get negativeColorTimingLabel => 'Farbabstimmung';

  @override
  String get negativeRedLabel => 'Rot (Cyan)';

  @override
  String get negativeGreenLabel => 'Grün (Magenta)';

  @override
  String get negativeBlueLabel => 'Blau (Gelb)';

  @override
  String get negativePrintGradeLabel => 'Gradation';

  @override
  String get negativeExposureLabel => 'Belichtung';

  @override
  String get negativeContrastLabel => 'Kontrast (Gradation)';

  @override
  String get negativeCompareHint =>
      'Vorschau gedrückt halten, um das Originalnegativ zu sehen.';

  @override
  String get negativeOriginalLabel => 'Originalnegativ';

  @override
  String get negativePreviewUnavailable =>
      'Für dieses Foto gibt es noch keine Vorschau.';

  @override
  String get negativeConvertButton => 'Umkehren und speichern';

  @override
  String negativeConvertAllButton(int count) {
    return 'Alle umkehren und speichern ($count)';
  }

  @override
  String negativeConvertingProgress(int current, int total) {
    return 'Umkehrung $current/$total…';
  }

  @override
  String negativeSavedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Positive gespeichert',
      one: '1 Positiv gespeichert',
    );
    return '$_temp0 neben den Originalen (_Positive.tiff).';
  }

  @override
  String negativeFailedMessage(String name) {
    return '$name konnte nicht umgekehrt werden.';
  }

  @override
  String get libraryMoveToAction => 'In Album verschieben…';

  @override
  String get libraryNewAlbumFromSelection => 'Neues Album mit diesen Fotos…';

  @override
  String get libraryPickAlbumTitle => 'In Album verschieben';

  @override
  String get libraryPickAlbumConfirm => 'Verschieben';

  @override
  String libraryMoveSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Fotos nicht verschoben: dort existieren bereits Dateien mit diesen Namen',
      one:
          '1 Foto nicht verschoben: dort existiert bereits eine Datei mit diesem Namen',
    );
    return '$_temp0';
  }

  @override
  String libraryMovingPhotos(int done, int total) {
    return 'Fotos werden verschoben... ($done/$total)';
  }

  @override
  String get libraryFolderExists =>
      'Dort existiert bereits ein Album mit diesem Namen';

  @override
  String get libraryEditTagsAction => 'Tags bearbeiten…';

  @override
  String get libraryEditTagsTitle => 'Tags, durch Kommas getrennt';

  @override
  String librarySelectedCount(int selected, int total) {
    return '$selected von $total ausgewählt';
  }

  @override
  String get aboutDialogTitle => 'Über darkmoon';

  @override
  String get aboutCredits => 'Entwickelt von Vini';

  @override
  String get splashLicense => 'GNU Affero General Public License v3.0';

  @override
  String get aboutThirdPartyLicenses => 'Lizenzen Dritter';

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
  String get sidebarOpenTooltip => 'Datei oeffnen oder Ordner hinzufuegen';

  @override
  String get sidebarFoldersSection => 'ALBEN';

  @override
  String get sidebarRemoveFolderTooltip => 'Album aus der Bibliothek entfernen';

  @override
  String get sidebarRemoveRecentFileTooltip =>
      'Aus zuletzt verwendeten Dateien entfernen';

  @override
  String get sidebarFolderNotFoundTooltip =>
      'Album nicht gefunden — aus der Liste entfernen';

  @override
  String get sidebarPresetsSection => 'VORGABEN';

  @override
  String get presetImportTooltip =>
      'Vorgaben importieren (.xmp, .zip, .lrtemplate, .pp3, .costyle)';

  @override
  String get presetSaveNewTooltip =>
      'Aktuelle Bearbeitung als Vorgabe speichern';

  @override
  String get presetTypeBadge => 'VORGABE';

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
  String get cropGuidedLabel => 'Geführt';

  @override
  String get cropGuidedTooltip =>
      'Zeichne eine Linie, die gerade oder lotrecht sein sollte';

  @override
  String get cropGuidedHint =>
      'Ziehe entlang einer Kante, die perfekt horizontal oder vertikal sein sollte — loslassen zum Ausrichten.';

  @override
  String get cropConstrainLabel => 'Beschnitt begrenzen';

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
  String get removeButton => 'Objekte entfernen';

  @override
  String get removeUnavailableMessage =>
      'Schalten Sie AI Enhance, Cloud AI oder Kolorieren aus, bevor Sie Objekte entfernen.';

  @override
  String get removePanelTitle => 'Objekte entfernen';

  @override
  String get removePanelHint =>
      'Übermalen Sie, was verschwinden soll, und drücken Sie Entfernen. Der Bereich wird aus seiner Umgebung gefüllt.';

  @override
  String get removeRunButton => 'Entfernen';

  @override
  String get removeClearStrokes => 'Leeren';

  @override
  String get removeDoneButton => 'Fertig';

  @override
  String get removeRunningMessage => 'Wird entfernt…';

  @override
  String removeRunningProgress(int done, int total) {
    return 'Wird entfernt… ($done/$total)';
  }

  @override
  String get removeFailedMessage =>
      'Die Entfernung konnte nicht berechnet werden. Die Modelldatei fehlt möglicherweise.';

  @override
  String get removeFailedStatus => 'Entfernen fehlgeschlagen';

  @override
  String removePatchName(int n) {
    return 'Entfernung $n';
  }

  @override
  String get removeGrowLabel => 'Erweitern';

  @override
  String get removeWithMaskLabel => 'Oder entfernen, was eine Maske abdeckt';

  @override
  String get removeWithMaskPlaceholder => 'Mit einer Maske entfernen…';

  @override
  String get removeListTitle => 'Entfernungen';

  @override
  String get removeVisibleTooltip => 'Angewendet — zum Ausblenden klicken';

  @override
  String get removeHiddenTooltip => 'Ausgeblendet — zum Anwenden klicken';

  @override
  String get removeDeleteTooltip => 'Diese Entfernung löschen';

  @override
  String get removeMaskNotReadyMessage =>
      'Diese Maske wird noch berechnet. Versuchen Sie es gleich noch einmal.';

  @override
  String get removeModeAi => 'KI-Füllung';

  @override
  String get removeModeClone => 'Klonen';

  @override
  String get removeModeHeal => 'Reparieren';

  @override
  String get removeModeGenerative => 'Generativ';

  @override
  String get removePickSourceButton => 'Quelle wählen';

  @override
  String get removePickSourceHint =>
      'Klicken Sie im Foto auf die Stelle, von der kopiert werden soll.';

  @override
  String get removeSourceDefaultHint =>
      'Quelle: neben dem Flicken (oder wählen).';

  @override
  String get removeSourcePickedHint => 'Quelle gesetzt.';

  @override
  String get removePromptLabel => 'Was stattdessen dort sein soll';

  @override
  String get removePromptHint => 'z. B. Gras, Himmel, Wand';

  @override
  String get removeGenerativeNotConfigured =>
      'Legen Sie zuerst die Adresse des generativen Servers in den Einstellungen (KI) fest.';

  @override
  String removeGenerativeFailedMessage(String error) {
    return 'Der generative Server hat keinen Flicken geliefert: $error';
  }

  @override
  String removeCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Entfernungen angewendet',
      one: '1 Entfernung angewendet',
    );
    return '$_temp0';
  }

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
  String get aiDenoiseEnhanceAfterEditsLabel =>
      'Auf das bearbeitete Foto anwenden';

  @override
  String get aiDenoiseEnhanceAfterEditsHint =>
      'Rauschunterdrückung, Details wiederherstellen und Detailschärfe laufen auf dem Foto mit den Bearbeitungen, in Vorschau und Export, statt auf der unberührten Quelle. Langsamer: sie laufen nach jeder Bearbeitung erneut.';

  @override
  String get aiDenoiseEnhanceAmountLabel => 'Stärke';

  @override
  String get aiDenoiseEnhanceRestoreDetailLabel => 'Details wiederherstellen';

  @override
  String get aiDenoiseEnhanceDetailSharpenLabel => 'Details schärfen';

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
  String get aiDenoiseEnhanceStageColorize => 'Kolorierung';

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
  String get photoStageOpening => 'Datei wird geöffnet ...';

  @override
  String get photoStageUnpacking => 'Sensordaten werden gelesen ...';

  @override
  String get photoStageProcessing => 'Wird entwickelt ...';

  @override
  String get photoStageExtracting => 'Bild wird vorbereitet ...';

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
  String get settingsPreviewResolutionNative => 'Nativ';

  @override
  String get settingsPreviewResolutionHint =>
      'Niedriger ist schneller beim Öffnen und Bearbeiten von Fotos; der Export verwendet immer die volle Sensorauflösung';

  @override
  String get settingsEditEmbeddedJpegLabel => 'Kamera-JPEG bearbeiten';

  @override
  String get settingsEditEmbeddedJpegHint =>
      'Bearbeitet eine RAW-Datei anhand der kamerainternen JPEG-Ausgabe statt der Sensordaten. Sie öffnet schneller und beginnt bei dem Look, den die Kamera beabsichtigt hat — ein gerendertes 8-Bit-Bild bietet aber deutlich weniger Spielraum, um einen ausgebrannten Himmel oder abgesoffene Schatten zu retten.';

  @override
  String get settingsCacheStorageLabel => 'Cache-Speicher';

  @override
  String get settingsCacheMeasuring => 'Wird gemessen ...';

  @override
  String settingsCacheUsedOf(String used, String limit) {
    return '$used von $limit';
  }

  @override
  String get settingsCachePreviews => 'Vorschauen';

  @override
  String get settingsCacheFullSources => 'Quellen in voller Auflösung';

  @override
  String get settingsCacheThumbnails => 'Miniaturansichten';

  @override
  String get settingsCacheAiResults => 'KI-Ergebnisse';

  @override
  String get settingsCacheLimitLabel => 'Cache-Grenze';

  @override
  String get settingsCacheLimitUnlimited => 'Keine Grenze';

  @override
  String get settingsCacheLimitHint =>
      'Vorschauen und Quellen in voller Auflösung werden älteste zuerst gelöscht, um darunter zu bleiben. KI-Ergebnisse werden nie automatisch gelöscht — sie neu zu berechnen kostet Minuten, nicht Sekunden.';

  @override
  String settingsClearCacheTooltip(String category) {
    return '$category leeren';
  }

  @override
  String get settingsClearAllCachesButton => 'Alle Caches leeren';

  @override
  String confirmClearCacheMessage(String category) {
    return 'Alles unter $category löschen? Es wird neu erstellt, sobald die Fotos wieder geöffnet werden.';
  }

  @override
  String get confirmClearAiCacheMessage =>
      'Alle KI-Ergebnisse löschen? Jedes hat Minuten an Rechenzeit gekostet, und sie erneut zu berechnen kostet diese Zeit wieder — nicht nur ein schnelles Neudekodieren.';

  @override
  String get confirmClearAllCachesMessage =>
      'Alle Caches löschen, auch die KI-Ergebnisse? Vorschauen und Miniaturansichten entstehen von selbst neu; KI-Ergebnisse müssen neu berechnet werden, was Minuten pro Foto dauert.';

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
  String get settingsXmpSidecarLabel => 'XMP-Begleitdateien schreiben';

  @override
  String get settingsXmpSidecarHint =>
      'Speichert die Bearbeitungen jedes Fotos in einer .xmp-Datei daneben, damit sie beim Verschieben mitkommen und von anderen Editoren gelesen werden können';

  @override
  String get settingsRemoveSidecarsButton =>
      'Die von dieser App geschriebenen .xmp-Dateien entfernen';

  @override
  String get confirmRemoveSidecarsMessage =>
      'Dadurch werden alle .xmp-Begleitdateien gelöscht, die darkmoon neben den Fotos in den Bibliotheksordnern geschrieben hat. Begleitdateien anderer Anwendungen bleiben erhalten. Deine Bearbeitungen bleiben im Katalog.';

  @override
  String removeSidecarsResultMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Begleitdateien entfernt',
      one: '1 Begleitdatei entfernt',
      zero: 'Keine darkmoon-Begleitdateien gefunden',
    );
    return '$_temp0';
  }

  @override
  String get settingsThumbnailThreadsLabel =>
      'Threads für das Laden von Miniaturansichten';

  @override
  String get settingsCustomDenoiseModelLabel =>
      'Benutzerdefiniertes Entrauschungsmodell';

  @override
  String get settingsCustomDenoiseModelHint =>
      'Ersetzt das On-Device-Denoise-Modell im Enhance-Tab des KI-Entrauschungsdialogs. Muss ein direkter Ersatz sein: 3-Kanal-RGB, gleiche Auflösung bei Ein-/Ausgabe, [0,1]-normalisiert (Tensor-Namen werden aus dem Modell gelesen, jede Benennung funktioniert) — ein Modell, das nicht passt, führt zu einem Fehler oder sichtbar falschem Ergebnis, nicht zu einem sauberen Fehlschlag.';

  @override
  String get settingsCustomDenoiseModelDefault => 'Standard (RealPLKSR)';

  @override
  String get settingsCustomDenoiseModelPickerTitle =>
      'Entrauschungsmodell wählen (.onnx)';

  @override
  String get settingsCustomDenoiseModelChooseButton => 'Datei wählen…';

  @override
  String get settingsGenerativeUrlLabel => 'Server für generatives Ersetzen';

  @override
  String get settingsGenerativeUrlHint =>
      'Adresse einer Solstice-kompatiblen Inpainting-Middleware (ComfyUI dahinter), genutzt von der generativen Füllung in Objekte entfernen. Nichts ist mitgeliefert: leer lassen, um den Modus aus zu lassen.';

  @override
  String get settingsGenerativeUrlPlaceholder => 'http://127.0.0.1:8000';

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
  String get filmstripRatingLabel => 'Bewertung';

  @override
  String get filmstripColorLabel => 'Farbmarkierung';

  @override
  String get labelNone => 'Keine';

  @override
  String get labelRed => 'Rot';

  @override
  String get labelYellow => 'Gelb';

  @override
  String get labelGreen => 'Grün';

  @override
  String get labelBlue => 'Blau';

  @override
  String get labelPurple => 'Lila';

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
  String filmstripDeleteConfirmManyMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Dadurch werden $count Fotos in den Papierkorb verschoben und ihre gespeicherten Bearbeitungen gelöscht. Du kannst die Fotos aus dem Papierkorb wiederherstellen, aber nicht die Bearbeitungen.',
    );
    return '$_temp0';
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
  String get sectionFilm => 'FILM';

  @override
  String get sectionReplaceColor => 'FARBE ERSETZEN';

  @override
  String get replaceColorPickButton => 'Eine Farbe im Foto wählen';

  @override
  String get replaceColorPickHint =>
      'Wählen Sie eine Farbe im Foto und verschieben Sie sie mit den Reglern.';

  @override
  String get replaceColorPickedHint =>
      'Gewählte Farbe. Erneut wählen, um sie zu ändern.';

  @override
  String get sliderReplaceColorTolerance => 'Bereich';

  @override
  String get sliderReplaceColorFeather => 'Weichheit';

  @override
  String get sliderReplaceColorHue => 'Farbton';

  @override
  String get sliderReplaceColorSaturation => 'Sättigung';

  @override
  String get sliderReplaceColorLuminance => 'Luminanz';

  @override
  String get sliderReplaceColorAmount => 'Stärke';

  @override
  String get filmNone => 'Keiner';

  @override
  String get filmImportTooltip => 'LUTs importieren (.cube, Hald-CLUT-Bild)';

  @override
  String get filmImportDialogTitle => 'LUTs importieren';

  @override
  String filmImportedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count LUTs',
      one: '1 LUT',
    );
    return '$_temp0 in die Filmliste importiert.';
  }

  @override
  String filmImportFailedMessage(String name, String error) {
    return '$name konnte nicht importiert werden: $error';
  }

  @override
  String get sliderFilmAmount => 'Film-Stärke';

  @override
  String get colorizeFilmLabel => 'Film-Look';

  @override
  String get gradeRangeMidtones => 'Mitteltöne';

  @override
  String get gradeRangeGlobal => 'Global';

  @override
  String get maskImageLayer => 'Originalbild';

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
  String get maskCloneTooltip => 'Maske duplizieren';

  @override
  String get maskCloneSuffix => 'Kopie';

  @override
  String get maskOkButton => 'OK';

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
  String histogramShadowClipping(String percent) {
    return 'Beschnittene Tiefen: $percent% des Bildes';
  }

  @override
  String histogramHighlightClipping(String percent) {
    return 'Beschnittene Lichter: $percent% des Bildes';
  }

  @override
  String get histogramNoShadowClipping => 'Keine beschnittenen Tiefen';

  @override
  String get histogramNoHighlightClipping => 'Keine beschnittenen Lichter';

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
  String get aiMaskFeatherLabel => 'Weichzeichnen';

  @override
  String get radialFeatherLabel => 'Weichzeichnen';

  @override
  String get linearFeatherLabel => 'Weichzeichnen';

  @override
  String get colorRangeHint => 'Auf das Bild tippen, um eine Farbe auszuwählen';

  @override
  String get maskWholeImage => 'Ganzes Bild';

  @override
  String get maskLuminance => 'Leuchtdichtebereich';

  @override
  String get maskFlow => 'Fluss';

  @override
  String get luminanceToleranceLabel => 'Toleranz';

  @override
  String get luminanceFeatherLabel => 'Weichzeichnen';

  @override
  String get maskSubject => 'Motiv';

  @override
  String get maskSky => 'Himmel';

  @override
  String get maskForeground => 'Vordergrund';

  @override
  String get maskDepth => 'Tiefe';

  @override
  String get subjectMaskHint =>
      'Einen Rahmen um das Motiv ziehen oder darauf tippen';

  @override
  String get depthNearLabel => 'Nah';

  @override
  String get depthFarLabel => 'Fern';

  @override
  String get depthFeatherLabel => 'Weichzeichnen';

  @override
  String get aiMaskComputing => 'Erkennung läuft…';

  @override
  String get aiMaskFailed => 'Erkennung fehlgeschlagen';

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
  String get colorProfileModeMissing => 'Eigenes Profil (nicht installiert)';

  @override
  String get colorProfileMissingWarning =>
      'Dieses Foto verwendet ein eigenes Farbprofil, das nicht installiert ist. Es wird mit Standard gerendert, bis das Profil importiert wird — das Foto merkt sich weiterhin, welches Profil es moechte.';

  @override
  String get sliderTexture => 'Textur';

  @override
  String get sliderClarity => 'Klarheit';

  @override
  String get sliderClarityShadows => 'Klarheit: Schatten';

  @override
  String get sliderClarityMidtones => 'Klarheit: Mitteltöne';

  @override
  String get sliderClarityHighlights => 'Klarheit: Lichter';

  @override
  String get sliderDehaze => 'Dunst entfernen';

  @override
  String get sliderCameraColor => 'Kamerafarbe';

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

  @override
  String get colorProfileEditorTitleNew => 'Neues Farbprofil';

  @override
  String get colorProfileEditorTitleEdit => 'Farbprofil bearbeiten';

  @override
  String get colorProfileEditorTabColor => 'Farbe';

  @override
  String get colorProfileEditorTabBase => 'Basis';

  @override
  String get colorProfileEditorToneHint =>
      'Bildet die Helligkeit neu ab und behält die Farbe. Punkt ziehen zum Formen, in den freien Bereich klicken zum Hinzufügen, Rechtsklick zum Entfernen.';

  @override
  String get colorProfileEditorPhotoSlidersHint =>
      'Diese beiden gelten für das geöffnete Foto, nicht für das Profil — sie stehen hier, weil eine Kurve erst dann etwas aussagt, wenn man sieht, wie stark sie angewendet wird.';

  @override
  String get colorProfileEditorBasicHint =>
      'Acht Farbtonbereiche. Jeder deckt drei der 24 Bins des Profils ab.';

  @override
  String get colorProfileEditorAdvancedHint =>
      'Alle 24 Farbton-Bins, einer alle 15 Grad.';

  @override
  String get colorProfileEditorModeBasic => 'Einfach';

  @override
  String get colorProfileEditorModeAdvanced => 'Erweitert';

  @override
  String get colorProfileEditorHue => 'Farbton';

  @override
  String get colorProfileEditorSaturation => 'Sättigung';

  @override
  String get colorProfileEditorLuminance => 'Luminanz';

  @override
  String get colorProfileEditorNameLabel => 'Profilname';

  @override
  String get colorProfileEditorNameTaken =>
      'Ein Profil mit diesem Namen existiert bereits. Beim Speichern wird eine Nummer angehängt.';

  @override
  String get colorProfileEditorResetHint =>
      'Setzt die Tonwertkurve und alle Farbtonanpassungen zurück. Der Name bleibt erhalten.';

  @override
  String get colorProfileEditorReset => 'Alles zurücksetzen';

  @override
  String get colorProfileNewTooltip => 'Farbprofil erstellen';

  @override
  String get hueRangeRed => 'Rot';

  @override
  String get hueRangeOrange => 'Orange';

  @override
  String get hueRangeYellow => 'Gelb';

  @override
  String get hueRangeGreen => 'Grün';

  @override
  String get hueRangeAqua => 'Türkis';

  @override
  String get hueRangeBlue => 'Blau';

  @override
  String get hueRangePurple => 'Violett';

  @override
  String get hueRangeMagenta => 'Magenta';

  @override
  String get colorProfileRenameTitle => 'Farbprofil umbenennen';

  @override
  String get colorProfileExportDialogTitle => 'Farbprofil exportieren';

  @override
  String get colorProfileImportDialogTitle => 'Farbprofil importieren';

  @override
  String get colorProfileImportFailed =>
      'Diese Datei konnte nicht als Farbprofil gelesen werden.';

  @override
  String get colorProfileDeleteTitle => 'Farbprofil loeschen';

  @override
  String colorProfileDeleteMessage(String name) {
    return '\"$name\" loeschen? Fotos, die es bereits verwenden, fallen auf Standard zurueck und weisen darauf hin; sie verwenden es wieder, wenn Sie es erneut importieren.';
  }

  @override
  String get colorProfileMenuTooltip => 'Farbprofil-Aktionen';

  @override
  String get colorProfileEditLabel => 'Bearbeiten';

  @override
  String get colorProfileDuplicateLabel => 'Duplizieren';

  @override
  String get colorProfileImportLabel => 'Importieren...';

  @override
  String get colorProfileEyedropper => 'Eine Farbe aus dem Foto waehlen';

  @override
  String get controlsTabAdjust => 'Anpassen';

  @override
  String get controlsTabColour => 'Farbe';

  @override
  String get controlsTabEffects => 'Effekte';

  @override
  String get settingsPanelLayoutLabel => 'Bearbeitungsbereich';

  @override
  String get settingsPanelLayoutTabbed => 'Registerkarten';

  @override
  String get settingsPanelLayoutFlat => 'Eine lange Liste';

  @override
  String get settingsTabStyleLabel => 'Tab-Beschriftung';

  @override
  String get settingsTabStyleText => 'Text';

  @override
  String get settingsTabStyleIcons => 'Symbole';

  @override
  String get settingsPresetThumbnailsLabel => 'Vorgaben-Vorschau';

  @override
  String get settingsPresetThumbnailsHint =>
      'Zeigt jede Vorgabe auf das aktuelle Foto angewendet';

  @override
  String get settingsPanelLayoutHint =>
      'Registerkarten gruppieren die Abschnitte in Anpassen, Farbe und Effekte. Masken bleiben in beiden Faellen oben angeheftet.';

  @override
  String get controlsTabDetails => 'Details';

  @override
  String get transformLevelButton => 'Ausrichten';

  @override
  String get transformLevelNothingFound =>
      'Nichts Gerades zum Ausrichten gefunden. Bitte manuell drehen.';

  @override
  String get transformAutoButton => 'Auto';

  @override
  String get transformAutoTooltip =>
      'Richtet das Foto aus und korrigiert stuerzende Vertikalen';

  @override
  String get transformVerticalButton => 'Vertikal';

  @override
  String get transformVerticalTooltip =>
      'Ausrichten und stuerzende Vertikalen korrigieren, auch bei schwachen Hinweisen';

  @override
  String get transformFullButton => 'Voll';

  @override
  String get transformFullTooltip =>
      'Korrigiert auch stuerzende Horizontalen — fuer Architektur, da es Landschaften verzerrt';

  @override
  String get transformAutoNothingFound =>
      'Nichts Gerades zum Korrigieren gefunden. Bitte manuell anpassen.';
}
