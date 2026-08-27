# PENDING — Compatibilidade de presets

**Meta:** o Darkmoon deve aplicar *qualquer* preset Lightroom/Camera Raw
(`.xmp`) sem perder ajustes. Hoje ele importa só o subconjunto de atributos
`crs:` que tem equivalente direto no pipeline de render. Os atributos sem
suporte são **ignorados silenciosamente** na aplicação do preset (não há
mais aviso na UI — ver `editor_screen.dart` `_applyPreset` e
`flutter_app/lib/presets/preset_xmp.dart`).

Cada preset ainda guarda a lista do que foi ignorado em
`Preset.unsupportedAttributes` (parseada em `_unsupportedAttributes`,
persistida em `preset_store.dart`) — só não é exibida. Isso serve de base
pra fechar o gap depois.

---

## Já suportado

White Balance (Temperature, Tint) · Exposure · Contrast · Highlights ·
Shadows · Whites · Blacks · Texture · Clarity · Dehaze · Vibrance ·
Saturation · Sharpening (Amount, Radius, Detail, Masking) · Post-Crop
Vignette (Amount, Midpoint, Feather) · Color Mixer / HSL (Hue, Saturation,
Luminance nos 8 canais) · Color Grading (Shadows, Midtones, Highlights,
Global — Hue/Sat/Lum) · Split Toning (fallback p/ Shadows/Highlights) ·
Tone Curve + Color Curves (Process Version 2012).

---

## Falta portar

### Alta prioridade (mudam bastante o resultado)
- **Redução de ruído**: `LuminanceSmoothing`, `LuminanceNoiseReductionDetail`,
  `LuminanceNoiseReductionContrast`, `ColorNoiseReduction`,
  `ColorNoiseReductionDetail`, `ColorNoiseReductionSmoothness`.
- **Curva paramétrica** (além dos pontos): `ParametricShadows`,
  `ParametricDarks`, `ParametricLights`, `ParametricHighlights`,
  `ParametricShadowSplit`, `ParametricMidtoneSplit`,
  `ParametricHighlightSplit`.
- **Calibração de câmera**: `RedHue`, `RedSaturation`, `GreenHue`,
  `GreenSaturation`, `BlueHue`, `BlueSaturation`, `ShadowTint`.
- **Perfil de câmera / look**: `CameraProfile`, `LookName`, `LookAmount`,
  `LookTable`, `ProfileGains`, tabelas RGB (`RequiresRGBTables`).

### Média prioridade
- **Correção de lente**: `LensProfileEnable`, `LensManualDistortionAmount`,
  `VignetteAmount`, `VignetteMidpoint` (vinheta de lente, diferente da
  post-crop), `DefringePurpleAmount`, `DefringeGreenAmount`,
  `DefringePurpleHueLo/Hi`, `DefringeGreenHueLo/Hi`.
- **Aberração cromática**: `ChromaticAberrationB`, `ChromaticAberrationR`.
- **Geometria / Upright**: `CropTop/Left/Bottom/Right`, `CropAngle`,
  `PerspectiveVertical`, `PerspectiveHorizontal`, `PerspectiveRotate`,
  `PerspectiveScale`, `PerspectiveAspect`, `PerspectiveUpright`.
- **Grão**: `GrainAmount`, `GrainSize`, `GrainFrequency`.

### White Balance — paridade total (futuro)
O seletor de modo (As Shot/Auto/Daylight/…) e o conta-gotas já existem, mas
o "As Shot" é uma **aproximação** do `cam_mul`/`cam_xyz` do LibRaw (McCamy +
matriz da câmera, sem dados espectrais) e o RAW ainda é decodificado com
`use_camera_wb = 1`. Paridade real com o Lightroom exigiria: decodificar o
RAW **sem** a WB da câmera, ler `AsShotNeutral`/`WB_Coeffs` e converter via o
perfil de câmera do Adobe (que o LibRaw não tem). O modelo de neutro por-foto
(`RenderParams.asShotKelvin/asShotTint`) já está pronto pra receber isso.

### Baixa prioridade / estrutural
- **Point Color** (`PointColors`) — ajuste de cor por amostra.
- **Máscaras / ajustes locais** (`MaskGroupBasedCorrections`,
  `CircularGradientBasedCorrections`, `PaintBasedCorrections`, etc.) —
  presets raramente carregam, e o app tem sistema de máscara próprio.
- **Healing / clone** (`RetouchAreas`, `RetouchInfo`).
- **HDR** (`HDREditMode`, ganhos HDR).

---

## Como fechar cada item

1. Mapear o atributo `crs:` para uma key de slider (ou uma nova) em
   `_directMappings` / lógica dedicada em `preset_xmp.dart`.
2. Implementar o efeito no pipeline (`render.dart` + `render_gpu.dart` +
   shader, se for o caso).
3. Remover o atributo do conjunto que cai em `_unsupportedAttributes`.
4. Teste de round-trip em `test/preset_xmp_test.dart` (exportar → importar
   → mesmos valores).
