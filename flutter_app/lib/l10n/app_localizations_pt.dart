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
  String get menuOpenFile => 'Abrir arquivo';

  @override
  String get menuOpenFolder => 'Adicionar pasta';

  @override
  String get menuSettings => 'Configurações';

  @override
  String get menuAbout => 'Sobre';

  @override
  String get aboutDialogTitle => 'Sobre o darkmoon';

  @override
  String get aboutCredits => 'Desenvolvido por Vini';

  @override
  String get splashLicense => 'GNU Affero General Public License v3.0';

  @override
  String get splashCopyright => '© 2026 Vini. Licenciado sob GNU AGPL v3.0.';

  @override
  String get splashLoading => 'Carregando sua biblioteca…';

  @override
  String get dialogOpenFolderTitle => 'Adicionar pasta';

  @override
  String get dialogOpenFileTitle => 'Abrir arquivo RAW';

  @override
  String get loadingFolder => 'Carregando pasta...';

  @override
  String loadingPhotos(int loaded, int total) {
    return 'Carregando fotos... ($loaded/$total)';
  }

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
  String photoNotFoundMessage(String name) {
    return '$name\nnão foi encontrada — pode ter sido movida, renomeada ou apagada fora do darkmoon';
  }

  @override
  String get sidebarRecentFilesSection => 'ARQUIVOS RECENTES';

  @override
  String get sidebarFoldersSection => 'PASTAS';

  @override
  String get sidebarRemoveFolderTooltip => 'Remover pasta';

  @override
  String get sidebarRemoveRecentFileTooltip => 'Remover dos arquivos recentes';

  @override
  String get sidebarFolderNotFoundTooltip =>
      'Pasta não encontrada — remova da lista';

  @override
  String get sidebarPresetsSection => 'PRESETS';

  @override
  String get presetImportTooltip => 'Importar presets (.xmp ou .zip)';

  @override
  String get presetSaveNewTooltip => 'Salvar edições atuais como preset';

  @override
  String get presetEmptyHint => 'Nenhum preset ainda';

  @override
  String presetAmountDialogTitle(String name) {
    return 'Aplicar \"$name\"';
  }

  @override
  String get presetAmountLabel => 'Intensidade';

  @override
  String get presetAmountApplyButton => 'Aplicar';

  @override
  String get presetRenameLabel => 'Renomear';

  @override
  String get presetExportLabel => 'Exportar';

  @override
  String get presetDeleteLabel => 'Excluir';

  @override
  String get presetSaveLabel => 'Salvar';

  @override
  String get presetSaveNewTitle => 'Salvar preset';

  @override
  String get presetRenameTitle => 'Renomear preset';

  @override
  String get presetExportDialogTitle => 'Exportar preset';

  @override
  String get presetExportManyTooltip => 'Exportar selecionados em .zip';

  @override
  String get presetExportManyDialogTitle => 'Exportar presets';

  @override
  String get presetImportDialogTitle => 'Importar presets';

  @override
  String presetDeleteConfirmMessage(String name) {
    return 'Excluir o preset \"$name\"? Essa ação não pode ser desfeita.';
  }

  @override
  String presetDeleteManyConfirmMessage(int count) {
    return 'Excluir $count presets? Essa ação não pode ser desfeita.';
  }

  @override
  String get presetSelectTooltip => 'Selecionar presets';

  @override
  String get presetSelectAllTooltip => 'Selecionar tudo';

  @override
  String presetSelectedCount(int count) {
    return '$count selecionado(s)';
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
  String get cropButton => 'Cortar e Transformar';

  @override
  String get sectionCropTransform => 'CORTAR E TRANSFORMAR';

  @override
  String get cropAspectLabel => 'Proporção';

  @override
  String get transformStraightenLabel => 'Endireitar';

  @override
  String get transformVerticalLabel => 'Vertical';

  @override
  String get transformHorizontalLabel => 'Horizontal';

  @override
  String get transformAspectLabel => 'Proporção';

  @override
  String get transformScaleLabel => 'Escala';

  @override
  String get cropRotateLeftTooltip => 'Girar 90° à esquerda';

  @override
  String get cropRotateRightTooltip => 'Girar 90° à direita';

  @override
  String get cropDoneButton => 'OK';

  @override
  String get undoButton => 'Desfazer';

  @override
  String get redoButton => 'Refazer';

  @override
  String get aiDenoiseButton => 'Redução de Ruído com IA';

  @override
  String get aiDenoiseDialogTitle => 'Redução de Ruído com IA';

  @override
  String get aiDenoiseDialogMessage =>
      'Reduz o ruído automaticamente, ajustado para manter os detalhes nítidos.';

  @override
  String get aiDenoiseLevelOff => 'Desligado';

  @override
  String get aiDenoiseLevelLight => 'Leve';

  @override
  String get aiDenoiseLevelMedium => 'Médio';

  @override
  String get aiDenoiseLevelStrong => 'Forte';

  @override
  String get aiDenoiseApplyButton => 'Aplicar';

  @override
  String get aiDenoiseApplyingMessage => 'Aplicando redução de ruído com IA...';

  @override
  String get aiDenoiseDisablingMessage =>
      'Desativando redução de ruído com IA...';

  @override
  String get aiDenoiseTabClassic => 'Clássico';

  @override
  String get aiDenoiseTabEnhance => 'Enhance';

  @override
  String get aiDenoiseTabCloud => 'IA na nuvem';

  @override
  String get aiDenoiseCloudMessage =>
      'Manda essa foto pra um provedor de IA na nuvem que você já tem conta e chave de API. Custa dinheiro de verdade por foto e envia a foto pra um terceiro — a aba Enhance é grátis e roda só no seu computador.';

  @override
  String get aiDenoiseCloudProviderLabel => 'Provedor';

  @override
  String get aiDenoiseCloudProviderOff => 'Desligado';

  @override
  String get aiDenoiseCloudProviderTopaz => 'Topaz Labs (Denoise)';

  @override
  String get aiDenoiseCloudProviderOpenAi => 'OpenAI (gpt-image-1)';

  @override
  String get aiDenoiseCloudProviderGemini => 'Google Gemini';

  @override
  String get aiDenoiseCloudTokenLabel => 'Chave de API';

  @override
  String get aiDenoiseCloudTokenHint => 'Cole sua chave de API';

  @override
  String get aiDenoiseCloudDisclosure =>
      'Guardada só neste computador (Windows Credential Manager), enviada só pro provedor escolhido. Cada aplicação envia a foto em resolução total e é cobrada pela sua conta no provedor — os resultados ficam em cache, então reabrir ou exportar a mesma foto não chama de novo.';

  @override
  String get aiDenoiseCloudGenerativeWarning =>
      'Esse provedor recria a imagem a partir de um prompt em vez de rodar um modelo dedicado de denoise — pode alterar detalhes finos (rostos, texto, textura), não só remover ruído.';

  @override
  String aiDenoiseCloudFailedMessage(String error) {
    return 'O denoise na nuvem falhou: $error';
  }

  @override
  String get aiDenoiseCloudFailedStatus => 'Denoise na nuvem falhou';

  @override
  String get aiDenoiseCloudStartingMessage => 'Iniciando denoise na nuvem…';

  @override
  String get aiDenoiseCloudStageUploading => 'Enviando foto…';

  @override
  String get aiDenoiseCloudStageProcessing => 'Processando…';

  @override
  String get aiDenoiseCloudStageDownloading => 'Baixando resultado…';

  @override
  String get aiDenoiseCloudStageDecoding => 'Decodificando foto…';

  @override
  String get aiDenoiseEnhanceMessage =>
      'Remove ruído, elimina grão de filme e dobra a resolução usando uma rede neural — mais perto de como o detalhe real da foto era antes do ruído e da compressão. Roda bem mais devagar que o Clássico, principalmente sem uma GPU compatível.';

  @override
  String get aiDenoiseEnhanceDenoiseLabel => 'Denoise';

  @override
  String get aiDenoiseEnhanceAmountLabel => 'Intensidade';

  @override
  String get aiDenoiseEnhanceRestoreDetailLabel => 'Restaurar detalhe';

  @override
  String get aiDenoiseEnhanceUpscaleLabel => 'Upscale 2x';

  @override
  String get aiDenoiseEnhanceSharpnessLabel => 'Nitidez';

  @override
  String get aiDenoiseEnhanceSharpnessCaption =>
      'Mistura um modelo mais lento que reconstrói mais detalhe — qualquer valor acima de 0% custa ~3min30s por foto de 24MP em vez de poucos segundos, e pode alterar levemente (não só afiar) texto ou detalhes bem pequenos.';

  @override
  String get aiDenoiseEnhanceRawDenoiseLabel =>
      'Denoise em RAW (antes do demosaic)';

  @override
  String get aiDenoiseEnhanceRawDenoiseUnavailableCaption =>
      'Só disponível para arquivos RAW com sensor Bayer padrão (não X-Trans, Foveon, ou formatos que não são RAW).';

  @override
  String get aiDenoiseEnhanceFailedMessage =>
      'O AI Enhance não conseguiu rodar nessa foto. Foi desligado de novo.';

  @override
  String aiDenoiseCustomModelFallbackMessage(String error) {
    return 'Seu modelo de denoise customizado não pôde ser usado ($error) — usado o modelo padrão no lugar.';
  }

  @override
  String get aiDenoiseCustomModelFallbackStatus =>
      'Modelo customizado falhou, usado o padrão';

  @override
  String get aiDenoiseEnhanceCpuWarning =>
      'Sua GPU ainda não é compatível com isso, então vai rodar na CPU — isso vai demorar bem mais.';

  @override
  String get aiDenoiseEnhanceGpuIncompatibleWarning =>
      'Sua GPU ainda não é compatível com isso, então vai rodar na CPU — espere que isso demore bem mais (até alguns minutos numa foto grande).';

  @override
  String get aiDenoiseEnhanceStartingMessage => 'Rodando AI Enhance...';

  @override
  String get aiDenoiseEnhanceStageDenoise => 'Removendo ruído';

  @override
  String get aiDenoiseEnhanceStageUpscale => 'Ampliando';

  @override
  String get aiDenoiseEnhanceStageRawDenoise => 'Removendo ruído (RAW)';

  @override
  String get aiDenoiseEnhanceStageDetailRestore => 'Restaurando detalhe';

  @override
  String get aiDenoiseEnhanceStageDetailSharpen =>
      'Aplicando nitidez ao detalhe';

  @override
  String get aiDenoiseEnhanceStageSharpen => 'Aplicando nitidez';

  @override
  String aiDenoiseEnhanceTileProgress(String stage, int percent) {
    return '$stage — $percent%';
  }

  @override
  String get exportPanelButton => 'Exportar';

  @override
  String get exportingButton => 'Exportando...';

  @override
  String get exportStageDecoding => 'Decodificando RAW...';

  @override
  String get exportStageRendering => 'Aplicando edições...';

  @override
  String get exportStageEncoding => 'Codificando...';

  @override
  String get exportStageWriting => 'Salvando arquivo...';

  @override
  String get exportPhotoDialogTitle => 'Exportar foto';

  @override
  String get exportRapidLabel => 'Exportação rápida';

  @override
  String get exportRapidHint => 'JPEG comprimido pra redes sociais';

  @override
  String get exportRapidScaleLabel => 'Resolução';

  @override
  String exportRapidScaleResultLabel(int width, int height) {
    return '≈ $width × $height px';
  }

  @override
  String get exportFormatLabel => 'Formato';

  @override
  String get exportQualityLabel => 'Qualidade';

  @override
  String get exportDialogConfirm => 'Exportar';

  @override
  String get cancelButton => 'Cancelar';

  @override
  String get copyButton => 'Copiar';

  @override
  String get hideButton => 'Ocultar';

  @override
  String exportSuccessMessage(String path) {
    return 'Exportado para $path';
  }

  @override
  String get exportDoneStatus => 'Pronto!';

  @override
  String get exportFailedStatus => 'Falha ao exportar';

  @override
  String get aiDenoiseEnhanceFailedStatus => 'AI Enhance falhou';

  @override
  String exportFailureMessage(String error) {
    return 'Falha ao exportar: $error';
  }

  @override
  String get resetTooltip => 'Redefinir ajustes';

  @override
  String get settingsDialogTitle => 'Configurações';

  @override
  String get settingsTabGeneral => 'Geral';

  @override
  String get settingsTabPerformance => 'Performance';

  @override
  String get settingsTabColor => 'Cor';

  @override
  String get settingsTabData => 'Dados';

  @override
  String get settingsLanguageLabel => 'Idioma';

  @override
  String get settingsLanguageAuto => 'Automático (sistema)';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguagePortuguese => 'Português';

  @override
  String get settingsLanguageGerman => 'Alemão';

  @override
  String get settingsFastPreviewLabel =>
      'Preview rápido ao arrastar os sliders';

  @override
  String get settingsPreviewResolutionLabel => 'Resolução do preview';

  @override
  String get settingsPreviewResolutionHint =>
      'Quanto menor, mais rápido para abrir e editar fotos; a exportação sempre usa a resolução total do sensor';

  @override
  String get settingsRawOnlyLabel => 'Somente arquivos RAW';

  @override
  String get settingsRawOnlyHint =>
      'Oculta JPEG, PNG e outros formatos comuns de imagem da biblioteca';

  @override
  String get settingsAnimationsLabel => 'Animações da interface';

  @override
  String get settingsAnimationsHint =>
      'Transições suaves nas seções do painel, troca de abas, zoom e no preview após uma edição';

  @override
  String get settingsGpuRenderLabel =>
      'Usar renderização por GPU (experimental)';

  @override
  String get settingsGpuRenderHint =>
      'Renderiza na placa de vídeo em vez da CPU; volta automaticamente para a CPU se não houver suporte';

  @override
  String get settingsDynamicFullPreviewLabel =>
      'Preview dinâmico em resolução total';

  @override
  String get settingsDynamicFullPreviewHint =>
      'Um instante depois que a edição assenta, re-renderiza na resolução nativa do sensor pra imagem ampliada ficar nítida. As fontes decodificadas ficam em cache no disco.';

  @override
  String get settingsFullQualityScaleLabel => 'Resolução do preview';

  @override
  String get settingsBaseContrastLabel => 'Perfil darkmoon Color';

  @override
  String get settingsBaseContrastHint =>
      'Uma curva de contraste fixa aplicada em toda foto antes das suas edições — o equivalente no darkmoon ao contraste de perfil que o Lightroom já embute. Aumente se presets importados do Lightroom ficam sem contraste, diminua (0 = desligado) pra um ponto de partida neutro. Muda toda foto e todo preset.';

  @override
  String get settingsThumbnailThreadsLabel =>
      'Threads de carregamento de miniaturas';

  @override
  String get settingsCustomDenoiseModelLabel => 'Modelo de denoise customizado';

  @override
  String get settingsCustomDenoiseModelHint =>
      'Substitui o modelo de Denoise on-device na aba Enhance do diálogo AI Denoise. Precisa ser um substituto direto: RGB 3 canais, mesma resolução de entrada/saída, nomes de tensor \"input\"/\"output\", valores normalizados [0,1] — um modelo que não seguir isso vai dar erro ou produzir um resultado visivelmente errado, não uma falha limpa.';

  @override
  String get settingsCustomDenoiseModelDefault => 'Padrão (RealPLKSR)';

  @override
  String get settingsCustomDenoiseModelPickerTitle =>
      'Escolha um modelo de denoise (.onnx)';

  @override
  String get settingsCustomDenoiseModelChooseButton => 'Escolher arquivo…';

  @override
  String get settingsCustomDenoiseModelResetButton => 'Redefinir';

  @override
  String get settingsClearThumbnailsButton => 'Limpar cache de miniaturas';

  @override
  String get settingsClearRecentFilesButton =>
      'Limpar histórico de arquivos recentes';

  @override
  String get settingsClearCatalogButton => 'Limpar catálogo (todas as edições)';

  @override
  String get settingsDevLoggingLabel => 'Modo desenvolvedor';

  @override
  String get settingsDevLoggingHint =>
      'Grava um log detalhado em disco (erros, status GPU/CPU do AI Enhance, etc.) pra relatar bugs. Desligado por padrão.';

  @override
  String get settingsOpenLogFolderButton => 'Abrir pasta de logs';

  @override
  String get confirmClearTitle => 'Limpar dados?';

  @override
  String get confirmClearThumbnailsMessage =>
      'Isso apaga todas as miniaturas em cache. Elas serão geradas novamente na próxima vez que você abrir uma pasta.';

  @override
  String get confirmClearRecentFilesMessage =>
      'Isso limpa sua lista de arquivos recentes. As pastas que você adicionou não são afetadas.';

  @override
  String get confirmClearCatalogMessage =>
      'Isso apaga permanentemente todas as edições salvas de todas as fotos. Essa ação não pode ser desfeita.';

  @override
  String get clearButton => 'Limpar';

  @override
  String get closeButton => 'Fechar';

  @override
  String get filmstripResetEditsAction => 'Resetar todas as edições';

  @override
  String get filmstripShowOnDiskAction => 'Mostrar no disco';

  @override
  String get filmstripDeleteAction => 'Excluir';

  @override
  String get imageContextCopyEditsAction => 'Copiar Edições';

  @override
  String get imageContextPasteEditsAction => 'Colar Edições';

  @override
  String get filmstripResetEditsConfirmTitle => 'Resetar todas as edições?';

  @override
  String filmstripResetEditsConfirmMessage(String name) {
    return 'Isso volta \"$name\" ao estado original — todo ajuste, curva e máscara. Não pode ser desfeito.';
  }

  @override
  String get filmstripDeleteConfirmTitle => 'Excluir foto?';

  @override
  String filmstripDeleteConfirmMessage(String name) {
    return 'Isso envia \"$name\" para a Lixeira e apaga suas edições salvas. Você pode restaurar a foto pela Lixeira, mas não as edições.';
  }

  @override
  String filmstripDeleteFailedMessage(String name, String error) {
    return 'Não foi possível excluir \"$name\": $error';
  }

  @override
  String get sectionWhiteBalance => 'BALANÇO DE BRANCO';

  @override
  String get sectionTone => 'TOM';

  @override
  String get sectionPresence => 'PRESENÇA';

  @override
  String get sectionDetail => 'DETALHE';

  @override
  String get sectionToneCurve => 'CURVA DE TOM';

  @override
  String get sectionColorCurve => 'CURVA DE COR';

  @override
  String get sectionColorMixer => 'MIXAGEM DE COR';

  @override
  String get sectionColorGrading => 'GRADAÇÃO DE COR';

  @override
  String get sectionEffects => 'EFEITOS';

  @override
  String get gradeRangeMidtones => 'Meios-tons';

  @override
  String get gradeRangeGlobal => 'Global';

  @override
  String get maskImageLayer => 'Imagem Completa';

  @override
  String get maskLinearGradient => 'Gradiente Linear';

  @override
  String get maskRadialGradient => 'Gradiente Radial';

  @override
  String get maskBrush => 'Pincel';

  @override
  String get maskAddTooltip => 'Adicionar máscara';

  @override
  String get maskEnabledLabel => 'Ativada';

  @override
  String get maskInvertLabel => 'Inverter';

  @override
  String get maskOpacityLabel => 'Opacidade';

  @override
  String get maskOverlayOpacityLabel => 'Opacidade da Marcação';

  @override
  String get maskCloneTooltip => 'Duplicar máscara';

  @override
  String get maskCloneSuffix => 'cópia';

  @override
  String get maskDeleteTooltip => 'Excluir máscara';

  @override
  String get maskResetTooltip => 'Redefinir esta máscara';

  @override
  String get maskClearAllTooltip => 'Limpar todas as máscaras';

  @override
  String get maskOverlayVisibleTooltip => 'Ocultar marcação da máscara';

  @override
  String get maskOverlayHiddenTooltip => 'Mostrar marcação da máscara';

  @override
  String get maskDisableTooltip => 'Desativar máscara';

  @override
  String get maskEnableTooltip => 'Ativar máscara';

  @override
  String get masksTitle => 'Máscaras';

  @override
  String get histogramTitle => 'Histograma';

  @override
  String get filmstripEditedTooltip => 'Editada';

  @override
  String get maskBrushSizeLabel => 'Tamanho do Pincel';

  @override
  String get maskBrushHardnessLabel => 'Dureza';

  @override
  String get maskBrushEraseLabel => 'Apagar';

  @override
  String get maskUndoStrokeTooltip => 'Desfazer último traço';

  @override
  String get maskColorRange => 'Faixa de Cor';

  @override
  String get colorRangeToleranceLabel => 'Tolerância';

  @override
  String get colorRangeFeatherLabel => 'Suavização';

  @override
  String get colorRangeHint => 'Toque na imagem para escolher uma cor';

  @override
  String get maskLuminance => 'Faixa de Luminância';

  @override
  String get maskFlow => 'Fluxo';

  @override
  String get luminanceToleranceLabel => 'Tolerância';

  @override
  String get luminanceFeatherLabel => 'Suavização';

  @override
  String get luminanceHint => 'Toque na imagem para escolher um brilho';

  @override
  String get flowAmountLabel => 'Fluxo';

  @override
  String get colorChannelRed => 'Vermelho';

  @override
  String get colorChannelOrange => 'Laranja';

  @override
  String get colorChannelYellow => 'Amarelo';

  @override
  String get colorChannelGreen => 'Verde';

  @override
  String get colorChannelAqua => 'Água-marinha';

  @override
  String get colorChannelBlue => 'Azul';

  @override
  String get colorChannelPurple => 'Roxo';

  @override
  String get colorChannelMagenta => 'Magenta';

  @override
  String get mixerHueLabel => 'Matiz';

  @override
  String get mixerSaturationLabel => 'Saturação';

  @override
  String get mixerLuminanceLabel => 'Luminância';

  @override
  String get mixerModeMixerLabel => 'Mixer';

  @override
  String get mixerModeHslLabel => 'HSL';

  @override
  String get sliderTemperature => 'Temperatura';

  @override
  String get sliderTint => 'Matiz';

  @override
  String get wbModeAsShot => 'Como capturada';

  @override
  String get wbModeAuto => 'Automático';

  @override
  String get wbModeDaylight => 'Luz do dia';

  @override
  String get wbModeCloudy => 'Nublado';

  @override
  String get wbModeShade => 'Sombra';

  @override
  String get wbModeTungsten => 'Tungstênio';

  @override
  String get wbModeFluorescent => 'Fluorescente';

  @override
  String get wbModeFlash => 'Flash';

  @override
  String get wbModeCustom => 'Personalizado';

  @override
  String get wbEyedropperTooltip =>
      'Clique num cinza neutro para definir o balanço de branco';

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

  @override
  String get sliderSharpenAmount => 'Nitidez';

  @override
  String get sliderSharpenRadius => 'Raio';

  @override
  String get sliderSharpenDetail => 'Detalhe';

  @override
  String get sliderSharpenMasking => 'Máscara de Bordas';

  @override
  String get sliderVignetteAmount => 'Quantidade da Vinheta';

  @override
  String get sliderVignetteMidpoint => 'Ponto Médio da Vinheta';

  @override
  String get sliderVignetteFeather => 'Suavização da Vinheta';

  @override
  String get sliderGrainAmount => 'Quantidade do Grão';

  @override
  String get sliderGrainSize => 'Tamanho do Grão';

  @override
  String get sliderGrainRoughness => 'Aspereza do Grão';

  @override
  String get sliderParamCurveShadows => 'Sombras';

  @override
  String get sliderParamCurveDarks => 'Escuros';

  @override
  String get sliderParamCurveLights => 'Claros';

  @override
  String get sliderParamCurveHighlights => 'Realces';

  @override
  String get sliderParamCurveShadowSplit => 'Divisão das Sombras';

  @override
  String get sliderParamCurveMidtoneSplit => 'Divisão dos Médios';

  @override
  String get sliderParamCurveHighlightSplit => 'Divisão dos Realces';

  @override
  String get toneCurveParametricLabel => 'Paramétrica';

  @override
  String get sectionLensCorrection => 'CORREÇÃO DE LENTE';

  @override
  String get lensCorrectionNoProfileFound => 'Nenhum perfil encontrado';

  @override
  String get lensCorrectionProfileLabel => 'Perfil da Lente';

  @override
  String get lensCorrectionAutoDetect => 'Detectar automaticamente';

  @override
  String get lensCorrectionDistortionLabel => 'Distorção';

  @override
  String get lensCorrectionVignetteLabel => 'Vinhetagem';

  @override
  String get lensCorrectionChromaticAberrationLabel => 'Aberração Cromática';

  @override
  String get lensCorrectionSearchHint => 'Buscar lentes…';

  @override
  String get lensCorrectionSearchNoMatches => 'Nenhum resultado';
}
