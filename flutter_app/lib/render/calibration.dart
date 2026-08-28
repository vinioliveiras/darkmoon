/// ============================================================================
///  ARQUIVO DE CALIBRAÇÃO — o "quanto" de cada slider
/// ============================================================================
///
/// Aqui ficam, num lugar só, os números que controlam **a força e o formato**
/// de cada ajuste da aplicação. A escala que você vê na tela (ex.: Exposure
/// -5..+5, Contrast -100..+100) NÃO muda — o que muda é o quanto aquele valor
/// realmente empurra a imagem.
///
/// COMO USAR
///   1. Edite um número abaixo.
///   2. Rode a build:  flutter run -d windows     (ou build windows --release)
///   3. Abra uma foto, mexa no slider correspondente e compare (ex.: com o
///      Lightroom no mesmo valor).
///   4. Não gostou? Volte pro valor "padrão:" anotado no comentário.
///
/// REGRA GERAL
///   • Cada comentário diz pra que lado mexer ("↑ maior = mais forte" etc.).
///   • Comece com passos pequenos (ex.: 0.42 → 0.50, não 0.42 → 2.0).
///   • Mudar aqui afeta TODAS as fotos e TODOS os presets.
///
/// CPU x GPU
///   Estes valores valem para o render em CPU (o padrão da aplicação e o que
///   você testa). O render em GPU (Configurações → opção avançada, desligado
///   por padrão) ainda usa os números fixos dentro dos shaders `.frag`; quando
///   um valor também existe no shader, o comentário marca com  [também no GPU:
///   arquivo.frag]  pra você casar os dois na mão se usar GPU.
///
/// Sem imports de Flutter de propósito: as funções de render rodam em isolates
/// e leem estas constantes direto, sem precisar passar nada.
library;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  WHITE BALANCE (Temperatura / Tonalidade)                                 ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Força do slider **Tonalidade (Tint)** — o quanto um Tint de ±100 empurra
/// verde contra magenta.
///   ↑ maior  = Tint mais agressivo (verde/magenta aparece mais rápido)
///   ↓ menor  = Tint mais suave
/// padrão: 0.35   (o modelo antigo usava 0.25; subimos rumo ao Lightroom)
const double calWbTintStrength = 0.35;

/// Gama do espaço de trabalho em que os ganhos de WB são aplicados.
/// Isto é técnico — só mexa se souber o motivo. Mudar desalinha a Temperatura
/// do "As Shot" (o ponto neutro por foto).
/// padrão: 2.2
const double calWbWorkingGamma = 2.2;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BÁSICO — Exposição / Brilho / Contraste                                  ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Exposição**: quantas unidades do slider equivalem a 1 stop (dobrar/
/// metade da luz). O efeito é  2^(valorDoSlider / este número).
///   ↑ maior  = Exposure mais fraca (precisa arrastar mais pra mesma mudança)
///   ↓ menor  = Exposure mais forte
/// padrão: 20.0
const double calExposureUnitsPerStop = 20.0;

/// **Brilho**: igual à Exposição, unidades do slider por stop, mas o Brilho
/// usa uma curva que protege pretos e brancos (não estoura as pontas).
///   ↑ maior  = Brilho mais fraco     ↓ menor = Brilho mais forte
/// padrão: 20.0
const double calBrightnessUnitsPerStop = 20.0;

/// **Brilho** — o quanto a curva concentra o efeito nos tons médios (em vez de
/// espalhar por toda a faixa).
///   ↑ maior  = mexe mais nos médios, pontas mais preservadas
///   ↓ menor  = efeito mais linear/parelho
/// padrão: 1.2
const double calBrightnessMidtoneStrength = 1.2;

/// **Contraste**: o quão forte o slider inclina a curva em S.
///   ↑ maior  = Contraste mais agressivo no mesmo valor
///   ↓ menor  = Contraste mais suave
/// padrão: 1.25
const double calContrastStrength = 1.25;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BÁSICO — Realces / Sombras / Brancos / Pretos                            ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Realces (Highlights)**: força da recuperação/estouro.
///   ↑ maior  = Highlights recupera/levanta muito mais rápido
///   ↓ menor  = mais sutil
/// padrão: 1.75
const double calHighlightsStrength = 1.75;

/// **Sombras (Shadows)**: multiplicador em cima do valor do slider.
///   ↑ maior  = Shadows mais forte     ↓ menor = mais fraco
/// padrão: 1.0
const double calShadowsAmountScale = 1.0;

/// **Sombras** — largura da faixa de tons afetada. É um expoente: número ALTO
/// concentra o efeito só nas sombras mais fechadas; número BAIXO espalha pros
/// tons médios-escuros também.
///   ↑ maior  = efeito mais restrito às sombras profundas
///   ↓ menor  = pega uma faixa maior de sombra (mais "Lightroom")
/// padrão: 4.5
const double calShadowsFalloff = 4.5;

/// **Brancos (Whites)** — a partir de que brilho o slider começa a agir.
/// É o piso de uma máscara (0..1 na luminância percebida).
///   ↑ maior (ex.: 0.5) = só os brancos mais claros mudam (efeito "fraco")
///   ↓ menor (ex.: 0.30) = pega também os médios-altos (efeito "forte")
/// padrão: 0.32     [também no GPU: point_ops_post_denoise.frag → rapidWhiteMask]
const double calWhitesMaskLow = 0.32;

/// **Brancos (Whites)** — o quanto ergue o ponto de branco no valor máximo.
///   ↑ maior  = Whites +100 clareia muito mais
///   ↓ menor  = Whites +100 quase não muda
/// padrão: 0.42   (RapidRAW original: 0.25)   [também no GPU: point_ops_post_denoise.frag]
const double calWhitesLevelCoeff = 0.42;

/// **Pretos (Blacks)** — multiplicador em cima do valor do slider.
///   ↑ maior  = Blacks mais forte (afunda/levanta o preto muito mais)
///   ↓ menor  = Blacks mais fraco
/// padrão: 1.5   (RapidRAW original: 1.0)   [também no GPU: point_ops_post_denoise.frag]
const double calBlacksAmountScale = 1.5;

/// **Pretos (Blacks)** — largura da faixa afetada (expoente, igual ao de
/// Sombras).
///   ↑ maior (ex.: 12) = só o preto mais fechado muda
///   ↓ menor (ex.: 7)  = pega uma faixa maior de sombra
/// padrão: 9.0   (RapidRAW original: 12.0)   [também no GPU: point_ops_post_denoise.frag]
const double calBlacksFalloff = 9.0;

/// **Sombras/Pretos** — reforço de contraste local aplicado junto do
/// levantamento, pra imagem não ficar "chapada" ao abrir muito as sombras.
///   ↑ maior  = mais "punch" ao levantar sombras
///   ↓ menor  = levantamento mais plano
/// padrão: 1.3
const double calShadowBlacksStretch = 1.3;

/// **Sombras/Pretos** — mistura entre a curva pura (0.0) e a curva com o
/// reforço de contraste acima (1.0).
///   ↑ maior  = usa mais o reforço de contraste
///   ↓ menor  = usa mais a curva pura
/// padrão: 0.85
const double calShadowBlacksContrastMix = 0.85;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  PRESENÇA — Textura / Clareza / Remover Névoa (Dehaze)                    ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Textura** — raio (em pixels) do detalhe que ela realça. Pequeno = detalhe
/// bem fino (poros, fios); grande = detalhe mais grosso.
///   ↑ maior  = realça estruturas maiores
///   ↓ menor  = realça só o detalhe mais fino
/// padrão: 3.0
const double calTextureSigma = 3.0;

/// **Textura** — multiplicador de força em cima do slider.
///   ↑ maior  = Textura mais forte     ↓ menor = mais fraca
/// padrão: 1.0
const double calTextureStrength = 1.0;

/// **Clareza** — raio (em pixels) do contraste local. Grande de propósito
/// (contraste de médio alcance, tipo "definição").
///   ↑ maior  = efeito mais amplo/"halo" maior
///   ↓ menor  = efeito mais localizado
/// padrão: 25.0
const double calClaritySigma = 25.0;

/// **Clareza** — multiplicador de força em cima do slider.
///   ↑ maior  = Clareza mais forte     ↓ menor = mais fraca
/// padrão: 1.0
const double calClarityStrength = 1.0;

/// **Remover Névoa (Dehaze +)** — o quanto o slider positivo puxa a
/// transmissão pra baixo (= remove névoa). Este é o principal controle da
/// força do Dehaze.
///   ↑ maior (ex.: 0.85) = Dehaze muito agressivo (RapidRAW original)
///   ↓ menor (ex.: 0.45) = Dehaze bem suave
/// padrão: 0.55   [também no GPU: dehaze_apply.frag]
const double calDehazeTransmissionCoeff = 0.55;

/// **Remover Névoa** — piso da transmissão: impede o Dehage de "quebrar" a
/// imagem nos pontos de mais névoa. Mais alto = mais seguro/suave.
///   ↑ maior  = limita o efeito máximo (mais suave)
///   ↓ menor  = deixa o Dehaze ir mais fundo (pode estourar)
/// padrão: 0.22   (RapidRAW original: 0.15)   [também no GPU: dehaze_apply.frag]
const double calDehazeTransmissionFloor = 0.22;

/// **Remover Névoa** — o quanto satura a cor proporcional à névoa removida.
///   ↑ maior  = Dehaze deixa a cor mais "puxada"
///   ↓ menor  = Dehaze quase não mexe na saturação
/// padrão: 0.32   (RapidRAW original: 0.5)   [também no GPU: dehaze_apply.frag]
const double calDehazeSatBoost = 0.32;

/// **Adicionar Névoa (Dehaze −)** — força do lado negativo do slider (mistura
/// a imagem com a luz atmosférica, deixando "leitoso").
///   ↑ maior  = Dehaze negativo mais forte
///   ↓ menor  = mais sutil
/// padrão: 0.55   (RapidRAW original: 0.7)   [também no GPU: dehaze_apply.frag]
const double calDehazeAddMix = 0.55;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  COR — Vibração / Saturação                                               ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Vibração (Vibrance +)** — ganho do lado positivo. A Vibração já protege
/// tons de pele e cores já saturadas; este número é a força bruta antes disso.
///   ↑ maior  = Vibração +100 muito mais intensa
///   ↓ menor  = mais contida
/// padrão: 3.0
const double calVibranceStrength = 3.0;

/// **Vibração** — o quanto ela SEGURA o efeito em tons de pele (pra rosto não
/// ficar laranja). 1.0 = não segura nada; 0.0 = zera na pele.
///   ↑ maior (perto de 1) = pele satura junto com o resto
///   ↓ menor (perto de 0) = pele fica bem protegida
/// padrão: 0.6
const double calVibranceSkinDampen = 0.6;

/// **Saturação** — multiplicador em cima do slider (o efeito é
/// 1 + valorDoSlider/100 * este número).
///   ↑ maior  = Saturação mais forte     ↓ menor = mais fraca
/// padrão: 1.0
const double calSaturationStrength = 1.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  DETALHE — Nitidez (Sharpen)                                              ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Nitidez → Quantidade** — multiplicador de força em cima do slider.
///   ↑ maior  = Nitidez mais forte no mesmo valor
///   ↓ menor  = mais suave
/// padrão: 1.0
const double calSharpenStrength = 1.0;

/// **Nitidez → Detalhe** — o quanto o slider Detalhe injeta do detalhe mais
/// fino (vs. o contorno mais grosso).
///   ↑ maior  = Detalhe alto vira mais "micro-detalhe" (e mais ruído)
///   ↓ menor  = Detalhe mais comportado
/// padrão: 0.6
const double calSharpenDetailMix = 0.6;

/// **Nitidez → Mascaramento** — piso de "o que conta como borda de verdade"
/// (escala 0..255). Abaixo disso o Mascaramento trata como área lisa/ruído e
/// não afia.
///   ↑ maior  = afia só bordas bem fortes (protege mais o ruído)
///   ↓ menor  = afia detalhes mais fracos também
/// padrão: 6.0
const double calSharpenEdgeThreshold = 6.0;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  EFEITOS — Vinheta                                                        ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Vinheta → Quantidade** — força geral em cima do slider.
///   ↑ maior  = Vinheta escurece/clareia as bordas muito mais
///   ↓ menor  = Vinheta mais discreta
/// padrão: 0.8
const double calVignetteStrength = 0.8;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  EFEITOS — Grão de filme (Grain)                                          ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **Grão → Quantidade** — multiplicador de força em cima do slider.
///   ↑ maior  = grão mais visível no mesmo valor
///   ↓ menor  = grão mais sutil
/// padrão: 1.0
const double calGrainStrength = 1.0;

/// **Grão → Tamanho** — o tamanho (em pixels, na referência de 1080px) de cada
/// grão quando o slider Tamanho está em 0 e em 100. O grão é redimensionado
/// junto com a resolução da imagem, então o tamanho relativo fica igual no
/// preview e na exportação.
///   ↑ maior  = grão mais grosso
///   ↓ menor  = grão mais fino
/// padrão: 0.8 (no 0)  e  4.8 (no 100)
const double calGrainSizePxAt0 = 0.8;
const double calGrainSizePxAt100 = 4.8;

/// **Grão → Aspereza (Roughness)** — o slider mistura um ruído fino (0) com um
/// ruído mais irregular/grosseiro (100). Este número NÃO muda o efeito do
/// slider; ele é o quanto o ruído grosseiro é "esticado" em relação ao fino.
///   ↑ maior  = no 100 o grão fica com manchas maiores
///   ↓ menor  = no 100 o grão fica mais parecido com o fino
/// padrão: 0.6
const double calGrainRoughCoordScale = 0.6;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  REDUÇÃO DE RUÍDO (IA Denoise — Leve / Médio / Forte)                     ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// **IA Denoise** — multiplicador global na suavização de LUMINÂNCIA (o grão
/// preto-e-branco), aplicado nos 3 níveis.
///   ↑ maior  = borra mais o grão (perde mais detalhe fino)
///   ↓ menor  = preserva detalhe (deixa mais grão)
/// padrão: 1.0
const double calDenoiseLumaStrengthScale = 1.0;

/// **IA Denoise** — multiplicador global na suavização de COR (manchas
/// coloridas de ruído), aplicado nos 3 níveis.
///   ↑ maior  = tira mais mancha de cor
///   ↓ menor  = mais conservador
/// padrão: 1.0
const double calDenoiseChromaStrengthScale = 1.0;
