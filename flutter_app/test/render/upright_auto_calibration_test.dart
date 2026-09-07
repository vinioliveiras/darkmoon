import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/crop_transform.dart';
import 'package:darkmoon/render/upright_auto.dart';
import 'package:darkmoon/render/upright_lines.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where [calUprightVerticalGain] and [calUprightHorizontalGain] come
/// from.
///
/// Neither could be reasoned out on paper. The geometry pass does not
/// apply a symmetric keystone — it holds the bottom edge still and pulls
/// only the top corners in — so a slider value does not map to a change
/// in convergence by any tidy formula, and the sampling is bilinear on
/// top of that. So the gains are measured the way the Level sign was:
/// build a perspective whose convergence is known, push it through the
/// real `applyCropTransform`, and see what is left.
///
/// Set [_report] to true to print the measurements instead of asserting
/// on them, which is what to do when retuning.
const bool _report = false;

const int _w = 320;
const int _h = 320;

/// Draws softly-ramped bright lines that all pass through the vanishing
/// point at [vanishX], [vanishY] (in pixels from the frame centre),
/// crossing the horizontal centre line at each of [crossings].
///
/// Anti-aliased on purpose: a hard-thresholded band reads as a staircase
/// to a gradient operator, and a staircase is exactly the case the angle
/// estimators measure worst. An earlier round of this work chased a
/// "detector bug" that was only ever the test's own drawing.
Uint8List _converging({
  required double vanishX,
  required double vanishY,
  required List<double> crossings,
  bool transpose = false,
}) {
  final rgb = Uint8List(_w * _h * 3);
  for (final crossing in crossings) {
    // Direction from the crossing point to the vanishing point, and the
    // unit normal to it.
    final dx = vanishX - crossing;
    final dy = vanishY;
    final length = math.sqrt(dx * dx + dy * dy);
    final nx = dy / length;
    final ny = -dx / length;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final px = (transpose ? y : x) - _w / 2;
        final py = (transpose ? x : y) - _h / 2;
        final distance = ((px - crossing) * nx + py * ny).abs();
        final coverage = ((4.0 - distance) / 3.0).clamp(0.0, 1.0);
        if (coverage <= 0) {
          continue;
        }
        final value = (coverage * 255).round();
        final i = (y * _w + x) * 3;
        if (value > rgb[i]) {
          rgb[i] = value;
          rgb[i + 1] = value;
          rgb[i + 2] = value;
        }
      }
    }
  }
  return rgb;
}

/// Draws lines given as (tilt from horizontal in degrees, where the line
/// crosses the vertical centre line) — the natural way to describe a
/// scene's horizontals, as against [_converging]'s vanishing point.
Uint8List _tilted(List<(double, double)> lines) {
  final rgb = Uint8List(_w * _h * 3);
  for (final (tilt, y0) in lines) {
    final a = tilt * math.pi / 180.0;
    final nx = -math.sin(a);
    final ny = math.cos(a);
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final px = x - _w / 2;
        final py = y - _h / 2;
        final distance = (px * nx + (py - y0) * ny).abs();
        final coverage = ((4.0 - distance) / 3.0).clamp(0.0, 1.0);
        if (coverage <= 0) {
          continue;
        }
        final value = (coverage * 255).round();
        final i = (y * _w + x) * 3;
        if (value > rgb[i]) {
          rgb[i] = value;
          rgb[i + 1] = value;
          rgb[i + 2] = value;
        }
      }
    }
  }
  return rgb;
}

Uint8List _luma(Uint8List rgb, int width, int height) {
  final out = Uint8List(width * height);
  for (var i = 0; i < width * height; i++) {
    out[i] =
        (0.2126 * rgb[i * 3] +
                0.7152 * rgb[i * 3 + 1] +
                0.0722 * rgb[i * 3 + 2])
            .round()
            .clamp(0, 255);
  }
  return out;
}

/// The measured fan-out of [rgb], normalised by the frame's extent — the
/// same quantity Auto turns into a slider value.
double? _fanOut(
  Uint8List rgb,
  int width,
  int height, {
  required bool verticals,
}) {
  final lines = detectLines(
    _luma(rgb, width, height),
    width,
    height,
    maxLines: calUprightMaxLines.round(),
    minStrength: calUprightLineFloor,
  );
  final fit = fitConvergence(lines, verticals: verticals);
  if (fit == null) {
    return null;
  }
  return fit.slope * (verticals ? width : height);
}

/// Applies one Transform slider through the real geometry pass.
({Uint8List rgb, int width, int height}) _apply(
  Uint8List rgb, {
  double vertical = 0,
  double horizontal = 0,
}) {
  final result = applyCropTransform(
    rgb,
    _w,
    _h,
    CropTransformParams(vertical: vertical, horizontal: horizontal),
  );
  return (
    rgb: result.rgbBytes,
    width: result.width,
    height: result.height,
  );
}

void main() {
  // Verticals fanning out from a point above the frame: a building shot
  // from the ground, which is the case Auto exists for.
  final vertical = _converging(
    vanishX: 0,
    vanishY: -900,
    crossings: const [-120, -60, 0, 60, 120],
  );
  // The same, rotated a quarter turn: horizontals converging to one side.
  final horizontal = _converging(
    vanishX: 0,
    vanishY: -900,
    crossings: const [-120, -60, 0, 60, 120],
    transpose: true,
  );

  test('the vertical gain leaves no convergence behind', () {
    final before = _fanOut(vertical, _w, _h, verticals: true)!;

    if (_report) {
      // ignore: avoid_print
      print('vertical fan-out before = ${before.toStringAsFixed(4)}');
      for (final slider in [-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0]) {
        final corrected = _apply(vertical, vertical: slider);
        final after = _fanOut(
          corrected.rgb,
          corrected.width,
          corrected.height,
          verticals: true,
        );
        // ignore: avoid_print
        print(
          '  slider ${slider.toStringAsFixed(0).padLeft(4)} -> '
          'residual ${after?.toStringAsFixed(4) ?? "none"}  '
          '(implied gain ${after == null ? "-" : (slider / before).toStringAsFixed(2)})',
        );
      }
    }

    // What Auto itself would do, put through the real pass.
    final correction = uprightAutoFor(_luma(vertical, _w, _h), _w, _h)!;
    final corrected = _apply(vertical, vertical: correction.vertical);
    final after = _fanOut(
      corrected.rgb,
      corrected.width,
      corrected.height,
      verticals: true,
    );

    if (_report) {
      // ignore: avoid_print
      print('auto chose $correction, residual $after');
    }

    expect(
      correction.vertical.abs(),
      greaterThan(calUprightDeadZone),
      reason: 'a convergence this plain has to be corrected at all',
    );
    expect(
      after!.abs(),
      lessThan(before.abs() * 0.25),
      reason:
          'Auto must remove most of the convergence it measured; leaving '
          'more than a quarter means the gain is wrong, not the fit',
    );
  });

  test('the horizontal gain leaves no convergence behind', () {
    final before = _fanOut(horizontal, _w, _h, verticals: false)!;

    if (_report) {
      // ignore: avoid_print
      print('horizontal fan-out before = ${before.toStringAsFixed(4)}');
      for (final slider in [-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0]) {
        final corrected = _apply(horizontal, horizontal: slider);
        final after = _fanOut(
          corrected.rgb,
          corrected.width,
          corrected.height,
          verticals: false,
        );
        // ignore: avoid_print
        print(
          '  slider ${slider.toStringAsFixed(0).padLeft(4)} -> '
          'residual ${after?.toStringAsFixed(4) ?? "none"}',
        );
      }
    }

    // uprightMeasureFor, not uprightAutoFor: Auto declines this axis, for
    // reasons documented on it. The gain still has to be right, because
    // the measurement is what the Vertical and Full modes will use.
    final correction = uprightMeasureFor(_luma(horizontal, _w, _h), _w, _h)!;
    final corrected = _apply(horizontal, horizontal: correction.horizontal);
    final after = _fanOut(
      corrected.rgb,
      corrected.width,
      corrected.height,
      verticals: false,
    );

    expect(
      correction.horizontal.abs(),
      greaterThan(calUprightDeadZone),
      reason: 'a convergence this plain has to be corrected at all',
    );
    expect(
      after!.abs(),
      lessThan(before.abs() * 0.25),
      reason: 'Auto must remove most of the convergence it measured',
    );
  });

  test('a frame of parallel lines is left alone', () {
    // Straight up and down, evenly spaced: nothing to correct, and Auto
    // saying otherwise would be worse than Auto doing nothing.
    final parallel = _converging(
      vanishX: 0,
      vanishY: -1e9,
      crossings: const [-120, -60, 0, 60, 120],
    );
    final fan = _fanOut(parallel, _w, _h, verticals: true)!;
    expect(fan.abs(), lessThan(0.02));

    final correction = uprightAutoFor(_luma(parallel, _w, _h), _w, _h);
    expect(
      correction?.vertical ?? 0,
      0,
      reason: 'parallel verticals must not be keystoned',
    );
  });

  test('Auto declines the horizontal axis, however clear it looks', () {
    // The measurement sees it plainly...
    final measured = uprightMeasureFor(_luma(horizontal, _w, _h), _w, _h)!;
    expect(measured.horizontal.abs(), greaterThan(calUprightDeadZone));

    // ...and Auto still will not act on it. Not caution about weak
    // evidence — the evidence here is perfect. It is that a hillside
    // produces evidence just as perfect, and geometry cannot tell the
    // two apart. See uprightAutoFor.
    final auto = uprightAutoFor(_luma(horizontal, _w, _h), _w, _h);
    expect(auto?.horizontal ?? 0, 0);
  });

  test('a hillside is what makes the horizontal axis untrustworthy', () {
    // A terrace of roofs climbing a slope, with level water below: roofs
    // high in the frame, waterline low, tilt varying smoothly between.
    // Geometrically this IS a converging family, and nothing about it
    // says "these are roofs".
    final hillside = _tilted(const [
      (1.0, 120.0),
      (-1.0, 90.0),
      (2.0, 60.0),
      (18.0, -80.0),
      (22.0, -40.0),
      (15.0, -60.0),
      (20.0, -20.0),
    ]);
    final lines = detectLines(
      _luma(hillside, _w, _h),
      _w,
      _h,
      maxLines: calUprightMaxLines.round(),
      minStrength: calUprightLineFloor,
    );
    final fit = fitConvergence(lines, verticals: false)!;

    expect(
      (fit.slope * _h).abs(),
      greaterThan(fit.scatter * calUprightMinAgreement),
      reason:
          'this is the point: the agreement gate passes it comfortably, so '
          'no amount of tightening that gate would have saved the photo '
          'this was written for',
    );
    expect(
      uprightAutoFor(_luma(hillside, _w, _h), _w, _h)?.horizontal ?? 0,
      0,
      reason: 'only declining the axis outright does',
    );
  });
}
