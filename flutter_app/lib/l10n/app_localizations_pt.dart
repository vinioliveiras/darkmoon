// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get menuFile => 'Arquivo';

  @override
  String get menuOpenFile => 'Abrir arquivo...';

  @override
  String get menuOpenFolder => 'Abrir pasta...';

  @override
  String get menuSettings => 'Configurações...';

  @override
  String get dialogOpenFolderTitle => 'Abrir pasta';

  @override
  String get dialogOpenFileTitle => 'Abrir arquivo RAW';

  @override
  String get loadingFolder => 'Carregando pasta...';

  @override
  String loadingImage(String name) {
    return 'Carregando $name...';
  }

  @override
  String get applyingAdjustments => 'Aplicando ajustes...';

  @override
  String get emptyStateOpenFolder =>
      'Abra uma pasta com arquivos RAW para começar';

  @override
  String get noFolderOpen => 'Nenhuma pasta aberta';

  @override
  String decodingPhoto(String name) {
    return '$name\n(decodificando...)';
  }

  @override
  String get beforeLabel => 'Antes';

  @override
  String get afterLabel => 'Depois';

  @override
  String get zoomFit => 'Ajustar';

  @override
  String get fitToWindow => 'Ajustar à janela';

  @override
  String get beforeAfterButton => 'Antes/Depois (\\)';

  @override
  String get fullQualityButton => 'Qualidade Máxima';

  @override
  String get exportPanelButton => 'Exportar...';

  @override
  String get exportingButton => 'Exportando...';

  @override
  String get exportPhotoDialogTitle => 'Exportar foto';

  @override
  String get exportFormatLabel => 'Formato';

  @override
  String get exportQualityLabel => 'Qualidade';

  @override
  String get exportDialogConfirm => 'Exportar';

  @override
  String get cancelButton => 'Cancelar';

  @override
  String exportSuccessMessage(String path) {
    return 'Exportado para $path';
  }

  @override
  String exportFailureMessage(String error) {
    return 'Falha ao exportar: $error';
  }

  @override
  String get resetTooltip => 'Redefinir ajustes';

  @override
  String get settingsDialogTitle => 'Configurações';

  @override
  String get settingsLanguageLabel => 'Idioma';

  @override
  String get settingsLanguageAuto => 'Automático (sistema)';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguagePortuguese => 'Português';

  @override
  String get settingsFastPreviewLabel =>
      'Preview rápido ao arrastar os sliders';

  @override
  String get settingsAlwaysFullQualityLabel =>
      'Sempre abrir fotos em qualidade máxima';

  @override
  String get settingsThumbnailThreadsLabel =>
      'Threads de carregamento de miniaturas';

  @override
  String get closeButton => 'Fechar';

  @override
  String get sectionWhiteBalance => 'BALANÇO DE BRANCO';

  @override
  String get sectionTone => 'TOM';

  @override
  String get sectionPresence => 'PRESENÇA';

  @override
  String get sliderTemperature => 'Temperatura';

  @override
  String get sliderTint => 'Matiz';

  @override
  String get sliderExposure => 'Exposição';

  @override
  String get sliderBrightness => 'Brilho';

  @override
  String get sliderContrast => 'Contraste';

  @override
  String get sliderHighlights => 'Realces';

  @override
  String get sliderShadows => 'Sombras';

  @override
  String get sliderWhites => 'Brancos';

  @override
  String get sliderBlacks => 'Pretos';

  @override
  String get sliderTexture => 'Textura';

  @override
  String get sliderClarity => 'Claridade';

  @override
  String get sliderDehaze => 'Remoção de Neblina';

  @override
  String get sliderVibrance => 'Vibração';

  @override
  String get sliderSaturation => 'Saturação';
}
