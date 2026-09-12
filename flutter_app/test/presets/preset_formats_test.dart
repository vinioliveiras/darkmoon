import 'package:darkmoon/presets/preset_formats.dart';
import 'package:flutter_test/flutter_test.dart';

const _lrTemplate = '''
s = {
	id = "8A2C4A1E-0000-4B4C-9E0E-0123456789AB",
	internalName = "Filmatic Warm",
	title = "Filmatic Warm",
	type = "Develop",
	value = {
		settings = {
			Blacks2012 = -12,
			Clarity2012 = 18,
			Contrast2012 = 10,
			Exposure2012 = 0.35,
			HueAdjustmentRed = -5,
			SaturationAdjustmentBlue = 20,
			ColorGradeShadowHue = 210,
			ColorGradeShadowSat = 15,
			ToneCurveName2012 = "Custom",
			ToneCurvePV2012 = {
				0,
				0,
				64,
				58,
				255,
				255,
			},
			Temperature = 6200,
			Vibrance = 25,
			ProcessVersion = "11.0",
		},
		uuid = "0123",
	},
	version = 0,
}
''';

const _pp3 = '''
[Version]
AppVersion=5.10
Version=351

[Exposure]
Auto=false
Compensation=0.5
Brightness=5
Contrast=12
Saturation=-8

[Shadows & Highlights]
Enabled=true
Highlights=30
Shadows=40

[Vibrance]
Enabled=true
Pastels=20
Saturated=10

[White Balance]
Setting=Custom
Temperature=5200
Green=0.95

[Sharpening]
Enabled=true
Amount=400
Radius=0.8

[Dehaze]
Enabled=true
Strength=15

[Vignetting Correction]
Enabled=true
Amount=-30
Radius=60

[Film Simulation]
Enabled=true
ClutFilename=Color/Kodak/Kodak Portra 400 2.png
Strength=80
''';

const _coStyle = '''
<?xml version="1.0" encoding="utf-8"?>
<SL Engine="1300" Name="Punchy Teal">
  <E K="Exposure" V="0.4" />
  <E K="Contrast" V="15" />
  <E K="Saturation" V="8" />
  <E K="HighlightRecovery" V="25" />
  <E K="ShadowRecovery" V="35" />
  <E K="ClarityAmount" V="12" />
  <E K="ClarityStructure" V="6" />
  <E K="Kelvin" V="5600" />
  <E K="Tint" V="3" />
  <E K="VignettingAmount" V="-1.2" />
  <E K="SharpeningAmount" V="300" />
  <E K="ColorEditorLayers" V="…" />
</SL>
''';

void main() {
  group('.lrtemplate', () {
    test('reads the settings block with the crs names', () {
      final preset = presetFromLrTemplate(
        _lrTemplate,
        fallbackName: 'fallback',
      )!;
      expect(preset.name, 'Filmatic Warm');
      expect(preset.values['Blacks'], -12);
      expect(preset.values['Clarity'], 18);
      expect(preset.values['Contrast'], 10);
      expect(preset.values['Exposure'], closeTo(0.35, 1e-6)); // stops
      expect(preset.values['MixerRedHue'], -5);
      expect(preset.values['MixerBlueSaturation'], 20);
      expect(preset.values['GradeShadowsHue'], 210);
      expect(preset.values['GradeShadowsSaturation'], 15);
      expect(preset.values['Temperature'], 6200);
      expect(preset.values['Vibrance'], 25);
      // Absent settings stay absent — a preset only carries what it sets.
      expect(preset.values.containsKey('Tint'), isFalse);
      expect(preset.curves.tone.length, 3);
      expect(preset.curves.tone[1].x, closeTo(64 / 255, 1e-6));
      expect(preset.curves.tone[1].y, closeTo(58 / 255, 1e-6));
      expect(preset.curves.red.length, 2);
    });

    test('rejects a file without a settings block', () {
      expect(
        presetFromLrTemplate('s = { title = "x" }', fallbackName: 'x'),
        isNull,
      );
      expect(presetFromLrTemplate('', fallbackName: 'x'), isNull);
    });
  });

  group('.pp3', () {
    test('maps the RawTherapee sections onto our sliders', () {
      final preset = presetFromPp3(_pp3, fallbackName: 'Portrait')!;
      expect(preset.name, 'Portrait');
      expect(preset.values['Exposure'], closeTo(0.5, 1e-6)); // stops
      expect(preset.values['Brightness'], 5);
      expect(preset.values['Contrast'], 12);
      expect(preset.values['Saturation'], -8);
      expect(preset.values['Highlights'], -30);
      expect(preset.values['Shadows'], 40);
      expect(preset.values['Vibrance'], 15);
      expect(preset.values['Temperature'], 5200);
      expect(preset.values['Tint'], closeTo(5, 0.01));
      expect(preset.values['SharpenAmount'], closeTo(60, 0.01));
      expect(preset.values['SharpenRadius'], 0.8);
      expect(preset.values['Dehaze'], 15);
      expect(preset.values['VignetteAmount'], -30);
      expect(preset.values['VignetteMidpoint'], 60);
      expect(preset.values['Film'], 2);
      expect(preset.values['FilmAmount'], 80);
    });

    test('a disabled section and a Camera white balance are left out', () {
      final preset = presetFromPp3('''
[Version]
Version=351
[Sharpening]
Enabled=false
Amount=900
[White Balance]
Setting=Camera
Temperature=3000
''', fallbackName: 'x')!;
      expect(preset.values.containsKey('SharpenAmount'), isFalse);
      expect(preset.values.containsKey('Temperature'), isFalse);
    });

    test('rejects a file that is not a processing profile', () {
      expect(presetFromPp3('[Foo]\nBar=1\n', fallbackName: 'x'), isNull);
      expect(presetFromPp3('not ini at all', fallbackName: 'x'), isNull);
    });

    test('film names resolve to the bundled stock, whatever the folder', () {
      expect(bundledFilmIdForClutName('Kodak/Kodak Portra 400 3 +.png'), 2);
      expect(bundledFilmIdForClutName(r'C:\luts\Fuji\Fuji Velvia 50.png'), 7);
      expect(bundledFilmIdForClutName('Kodak Gold 200.png'), isNull);
    });
  });

  group('.costyle', () {
    test('maps the K/V entries onto our sliders', () {
      final preset = presetFromCoStyle(_coStyle, fallbackName: 'fallback')!;
      expect(preset.name, 'Punchy Teal');
      expect(preset.values['Exposure'], closeTo(0.4, 1e-6)); // stops
      expect(preset.values['Contrast'], 15);
      expect(preset.values['Saturation'], 8);
      expect(preset.values['Highlights'], -25);
      expect(preset.values['Shadows'], 35);
      expect(preset.values['Clarity'], 12);
      expect(preset.values['Texture'], 6);
      expect(preset.values['Temperature'], 5600);
      expect(preset.values['Tint'], 3);
      expect(preset.values['VignetteAmount'], closeTo(-30, 0.01));
      expect(preset.values['SharpenAmount'], closeTo(45, 0.01));
      expect(preset.unsupportedAttributes, ['ColorEditorLayers']);
    });

    test('rejects XML without entries and non-XML', () {
      expect(presetFromCoStyle('<SL/>', fallbackName: 'x'), isNull);
      expect(presetFromCoStyle('nope', fallbackName: 'x'), isNull);
    });
  });

  test('presetFromForeignFile routes by extension', () {
    expect(presetFromForeignFile('a.pp3', _pp3, fallbackName: 'a'), isNotNull);
    expect(
      presetFromForeignFile('a.COSTYLE', _coStyle, fallbackName: 'a'),
      isNotNull,
    );
    expect(
      presetFromForeignFile('a.lrtemplate', _lrTemplate, fallbackName: 'a'),
      isNotNull,
    );
    expect(
      presetFromForeignFile('a.xmp', _lrTemplate, fallbackName: 'a'),
      isNull,
    );
  });
}
