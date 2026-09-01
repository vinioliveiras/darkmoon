import 'package:flutter/material.dart';

import '../native/libraw.dart';
import '../theme.dart';

/// Formats a shutter speed in seconds as Meridian does: a plain decimal
/// with "s" for anything at or above one second, otherwise "1/N" rounded
/// to the nearest whole denominator (matching how cameras themselves
/// display shutter speed, e.g. 1/250 rather than 0.004s).
String _formatShutter(double seconds) {
  if (seconds <= 0) {
    return '—';
  }
  if (seconds >= 1) {
    return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)}s';
  }
  final denominator = (1 / seconds).round();
  return '1/$denominator';
}

String _formatAperture(double fNumber) =>
    fNumber <= 0 ? '—' : 'f/${fNumber.toStringAsFixed(fNumber < 10 ? 1 : 0)}';

String _formatIso(double iso) => iso <= 0 ? '—' : 'ISO ${iso.round()}';

String _formatFocalLength(double mm) => mm <= 0 ? '—' : '${mm.round()}mm';

/// Meridian-style capture info strip, shown below the histogram: camera
/// model, lens, and the exposure triangle (ISO/shutter/aperture) plus
/// focal length. Null [metadata] (still loading, or the file carries none
/// of this) renders nothing rather than a placeholder — this is
/// supplementary info, not something worth reserving layout space for.
class PhotoMetadataView extends StatelessWidget {
  const PhotoMetadataView({super.key, required this.metadata});

  final RawMetadata? metadata;

  @override
  Widget build(BuildContext context) {
    final data = metadata;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final camera = [
      data.cameraMake,
      data.cameraModel,
    ].where((s) => s.isNotEmpty).join(' ');
    final exposure = [
      _formatFocalLength(data.focalLengthMm),
      _formatAperture(data.apertureFNumber),
      _formatShutter(data.shutterSeconds),
      _formatIso(data.isoSpeed),
    ].where((s) => s != '—').join('  ·  ');

    if (camera.isEmpty && data.lensModel.isEmpty && exposure.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (camera.isNotEmpty)
            Text(
              camera,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DarkmoonColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (data.lensModel.isNotEmpty)
            Text(
              data.lensModel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DarkmoonColors.textMuted,
                fontSize: 10.5,
              ),
            ),
          if (exposure.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                exposure,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DarkmoonColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
