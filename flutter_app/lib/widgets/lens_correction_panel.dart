import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/lens_correction.dart';
import '../theme.dart';
import 'slider_row.dart';
import 'styled_dropdown.dart';

/// Meridian's Lens Corrections panel's Profile tab — matched-profile
/// display, a manual override picker, and the two Amount sliders. The
/// enable on/off toggle deliberately lives on this section's own
/// `_SectionHeader` switch in editor_screen.dart (wired straight to
/// [LensCorrectionParams.enabled]) rather than duplicated here, matching
/// how every other section's header switch already works.
class LensCorrectionPanel extends StatelessWidget {
  const LensCorrectionPanel({
    super.key,
    required this.params,
    required this.resolvedProfile,
    required this.allProfiles,
    required this.cameraMake,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final LensCorrectionParams params;

  /// The profile actually in effect right now (manual override if set and
  /// still present in [allProfiles], else the auto-detected match, else
  /// null) — shown as the "matched profile" line regardless of which path
  /// produced it, since from the user's point of view it's just "what's
  /// correcting this photo".
  final LensProfile? resolvedProfile;

  final List<LensProfile> allProfiles;

  /// The selected photo's camera maker (from EXIF) — narrows the manual
  /// picker to lenses plausibly mountable on this camera, since offering
  /// all ~1500 bundled profiles in one flat list would be both unusable
  /// and slow to lay out.
  final String cameraMake;

  final ValueChanged<LensCorrectionParams> onChanged;
  final ValueChanged<LensCorrectionParams> onChangeEnd;

  List<LensProfile> _candidateProfiles() {
    final makerLower = cameraMake.trim().toLowerCase();
    final filtered = makerLower.isEmpty
        ? allProfiles
        : allProfiles
              .where((p) => p.maker.toLowerCase().contains(makerLower))
              .toList();
    // Third-party lenses (Sigma/Tamron/Tokina) don't share the camera's
    // own maker string but are still valid candidates for any mount —
    // falling back to the full list when the maker filter empties it out
    // avoids a picker that can only ever show "no matches".
    return filtered.isEmpty ? allProfiles : filtered;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final candidates = _candidateProfiles();
    final selectedKey = params.manualProfileKeyHash == null
        ? null
        : resolvedProfile?.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          resolvedProfile == null
              ? l10n.lensCorrectionNoProfileFound
              : '${resolvedProfile!.maker} ${resolvedProfile!.model}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: resolvedProfile == null
                ? DarkmoonColors.textMuted
                : DarkmoonColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        StyledDropdown<String?>(
          label: l10n.lensCorrectionProfileLabel,
          value: selectedKey,
          placeholder: l10n.lensCorrectionAutoDetect,
          searchable: true,
          searchHintText: l10n.lensCorrectionSearchHint,
          noMatchesText: l10n.lensCorrectionSearchNoMatches,
          items: [
            StyledDropdownItem<String?>(
              value: null,
              label: l10n.lensCorrectionAutoDetect,
            ),
            for (final profile in candidates)
              StyledDropdownItem<String?>(
                value: profile.key,
                label: '${profile.maker} ${profile.model}',
              ),
          ],
          onChanged: (key) {
            final next = key == null
                ? params.copyWith(clearManualProfile: true)
                : params.copyWith(manualProfileKeyHash: lensProfileKeyHash(key));
            onChangeEnd(next);
          },
        ),
        const SizedBox(height: 14),
        SliderRow(
          name: l10n.lensCorrectionDistortionLabel,
          min: 0,
          max: 100,
          value: params.distortionAmount,
          decimals: 0,
          defaultValue: 0,
          onChanged: (v) =>
              onChanged(params.copyWith(distortionAmount: v)),
          onChangeEnd: (v) =>
              onChangeEnd(params.copyWith(distortionAmount: v)),
        ),
        const SizedBox(height: 10),
        SliderRow(
          name: l10n.lensCorrectionVignetteLabel,
          min: 0,
          max: 100,
          value: params.vignetteAmount,
          decimals: 0,
          defaultValue: 0,
          onChanged: (v) => onChanged(params.copyWith(vignetteAmount: v)),
          onChangeEnd: (v) => onChangeEnd(params.copyWith(vignetteAmount: v)),
        ),
        const SizedBox(height: 10),
        SliderRow(
          name: l10n.lensCorrectionChromaticAberrationLabel,
          min: 0,
          max: 100,
          value: params.chromaticAberrationAmount,
          decimals: 0,
          defaultValue: 100,
          onChanged: (v) =>
              onChanged(params.copyWith(chromaticAberrationAmount: v)),
          onChangeEnd: (v) =>
              onChangeEnd(params.copyWith(chromaticAberrationAmount: v)),
        ),
      ],
    );
  }
}
