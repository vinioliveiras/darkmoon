import 'package:flutter/material.dart';

/// The app's text-field border, after the fields of macOS 26: a rounded
/// hairline over a faintly lit fill, and when focused a soft halo around
/// the outline rather than a thicker line. The halo is what an
/// [OutlineInputBorder] cannot draw, so this subclass adds it and keeps
/// it through [copyWith], [scale] and the focus animation's lerps.
class GlassInputBorder extends OutlineInputBorder {
  const GlassInputBorder({
    super.borderSide,
    super.borderRadius = const BorderRadius.all(Radius.circular(8)),
    super.gapPadding,
    this.halo = const Color(0x00000000),
    this.haloWidth = 3.5,
  });

  /// The focus ring's colour; fully transparent paints nothing.
  final Color halo;

  /// How far the ring reaches outside the outline, in logical pixels.
  final double haloWidth;

  @override
  GlassInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    Color? halo,
    double? haloWidth,
  }) {
    return GlassInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      halo: halo ?? this.halo,
      haloWidth: haloWidth ?? this.haloWidth,
    );
  }

  @override
  GlassInputBorder scale(double t) {
    return GlassInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
      halo: halo,
      haloWidth: haloWidth * t,
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is OutlineInputBorder) {
      final fromHalo = a is GlassInputBorder ? a.halo : halo.withAlpha(0);
      final fromWidth = a is GlassInputBorder ? a.haloWidth : haloWidth;
      return GlassInputBorder(
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        gapPadding: a.gapPadding,
        halo: Color.lerp(fromHalo, halo, t)!,
        haloWidth: fromWidth + (haloWidth - fromWidth) * t,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is OutlineInputBorder) {
      final toHalo = b is GlassInputBorder ? b.halo : halo.withAlpha(0);
      final toWidth = b is GlassInputBorder ? b.haloWidth : haloWidth;
      return GlassInputBorder(
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        gapPadding: b.gapPadding,
        halo: Color.lerp(halo, toHalo, t)!,
        haloWidth: haloWidth + (toWidth - haloWidth) * t,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (halo.a > 0 && haloWidth > 0) {
      // A stroke centred on the outline's outer edge, so half of it lies
      // outside the field; that is the ring, the inner half is hidden by
      // the fill and the outline drawn over it.
      final outer = borderRadius.resolve(textDirection).toRRect(rect);
      canvas.drawRRect(
        outer.inflate(haloWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = haloWidth
          ..color = halo,
      );
    }
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is GlassInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding &&
        other.halo == halo &&
        other.haloWidth == haloWidth;
  }

  @override
  int get hashCode =>
      Object.hash(borderSide, borderRadius, gapPadding, halo, haloWidth);
}

/// The theme's field, capsule-shaped: search boxes, after the toolbar
/// search fields of macOS 26. Everything else (fill, hairline, halo)
/// comes from the theme so a search box and a plain field stay siblings.
InputDecoration capsuleInputDecoration(
  BuildContext context, {
  String? hintText,
  TextStyle? hintStyle,
  Widget? prefixIcon,
  Widget? suffixIcon,
  EdgeInsetsGeometry? contentPadding,
}) {
  final theme = Theme.of(context).inputDecorationTheme;
  const capsule = BorderRadius.all(Radius.circular(999));
  InputBorder? round(InputBorder? border) => border is OutlineInputBorder
      ? border.copyWith(borderRadius: capsule)
      : border;
  return InputDecoration(
    isDense: true,
    hintText: hintText,
    hintStyle: hintStyle,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: contentPadding,
    border: round(theme.border),
    enabledBorder: round(theme.enabledBorder),
    focusedBorder: round(theme.focusedBorder),
    disabledBorder: round(theme.disabledBorder),
    errorBorder: round(theme.errorBorder),
    focusedErrorBorder: round(theme.focusedErrorBorder),
  );
}
