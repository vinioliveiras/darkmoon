import 'dart:typed_data';

import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/color_profile_reference.dart';
import 'package:darkmoon/widgets/color_profile_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// This widget creates and replaces `ui.Image`s while a `RawImage` holds
/// them, which is the exact shape of bug that produced a grey rectangle
/// over every edit once before (see PreviewFrame). RenderImage takes
/// ownership of whatever it is handed and disposes it when replaced, so
/// handing it the widget's own image would be a double free — the tests
/// here mostly exist to notice when that stops being true.
void main() {
  ColorProfile profileWithHueShift(double degrees) => ColorProfile(
    tone: List<double>.of(identityColorProfile.tone),
    hueShift: List<double>.filled(colorProfileBins, degrees),
    satMul: List<double>.of(identityColorProfile.satMul),
    lumMul: List<double>.of(identityColorProfile.lumMul),
  );

  /// Pumps and lets the decode actually finish.
  ///
  /// `decodeImageFromPixels` completes through the engine, outside the
  /// fake clock `pumpAndSettle` drives, so settling alone never sees the
  /// image arrive and the widget stays empty. runAsync gives it a real
  /// event loop; the pump afterwards is what puts the result on screen.
  Future<void> pumpAndDecode(WidgetTester tester, Widget widget) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
  }

  Widget host(ColorProfile profile, Float32List source, int w, int h) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: ColorProfilePreview(
                source: source,
                sourceWidth: w,
                sourceHeight: h,
                profile: profile,
              ),
            ),
          ),
        ),
      );

  testWidgets('renders the reference chart', (tester) async {
    final chart = buildReferenceChart();
    await pumpAndDecode(
      tester,
      host(
        identityColorProfile,
        chart,
        referenceChartWidth,
        referenceChartHeight,
      ),
    );

    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, isNotNull);
    expect(raw.image!.width, referenceChartWidth);
    expect(raw.image!.height, referenceChartHeight);
  });

  testWidgets('changing the profile replaces the image without disposing '
      'one still in use', (tester) async {
    final chart = buildReferenceChart();
    await pumpAndDecode(
      tester,
      host(
        identityColorProfile,
        chart,
        referenceChartWidth,
        referenceChartHeight,
      ),
    );

    // Several changes in a row, the way a drag produces them. A double
    // free or a use-after-free surfaces as a thrown assertion from
    // dart:ui here rather than as anything visible.
    for (final degrees in [5.0, -12.0, 25.0, 0.0]) {
      await pumpAndDecode(
        tester,
        host(
          profileWithHueShift(degrees),
          chart,
          referenceChartWidth,
          referenceChartHeight,
        ),
      );
    }

    expect(tester.takeException(), isNull);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  testWidgets('disposing while a rebuild is in flight does not throw', (
    tester,
  ) async {
    final chart = buildReferenceChart();
    // Deliberately no wait for the decode: tear the widget down while it
    // is still in flight, which is what closing the dialog during a drag
    // does.
    await tester.pumpWidget(
      host(
        profileWithHueShift(10),
        chart,
        referenceChartWidth,
        referenceChartHeight,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the reference chart is neutral where the tone curve reads', (
    tester,
  ) async {
    // The bottom band is grey by construction so that the tone curve is
    // the only thing that can move it — applyColorProfile leaves
    // unsaturated pixels alone. If that band ever gains a colour cast,
    // the tone curve becomes impossible to judge there.
    final chart = buildReferenceChart();
    final y = referenceChartHeight - 4;
    for (var x = 0; x < referenceChartWidth; x += 37) {
      final i = (y * referenceChartWidth + x) * 3;
      expect(chart[i], chart[i + 1]);
      expect(chart[i + 1], chart[i + 2]);
    }
  });
}
