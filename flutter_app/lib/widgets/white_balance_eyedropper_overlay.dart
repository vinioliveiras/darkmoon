import 'package:flutter/material.dart';

/// A transparent full-image tap target shown over the preview while the
/// White Balance eyedropper is armed. A click reports the normalized
/// image coordinate; the editor samples the decoded source there and
/// solves for the Temperature/Tint that neutralizes it.
///
/// Intentionally minimal — no coverage shading (unlike ColorRangeOverlay),
/// just a precise cursor and a one-line hint.
class WhiteBalanceEyedropperOverlay extends StatelessWidget {
  const WhiteBalanceEyedropperOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.onSample,
    this.hint,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final void Function(double nx, double ny) onSample;
  final String? hint;

  Rect _imageRect() {
    final imageAspect = imageWidth / imageHeight;
    final containerAspect = containerSize.width / containerSize.height;
    double w, h;
    if (containerAspect > imageAspect) {
      h = containerSize.height;
      w = h * imageAspect;
    } else {
      w = containerSize.width;
      h = w / imageAspect;
    }
    return Rect.fromLTWH(
      (containerSize.width - w) / 2,
      (containerSize.height - h) / 2,
      w,
      h,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final rect = _imageRect();
          if (!rect.contains(details.localPosition)) {
            return;
          }
          final nx = ((details.localPosition.dx - rect.left) / rect.width)
              .clamp(0.0, 1.0);
          final ny = ((details.localPosition.dy - rect.top) / rect.height)
              .clamp(0.0, 1.0);
          onSample(nx, ny);
        },
        child: hint == null
            ? const SizedBox.expand()
            : Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    hint!,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
      ),
    );
  }
}
