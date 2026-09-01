import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../cloud_denoise/cloud_denoise_provider.dart';
import '../cloud_denoise/cloud_denoise_token_store.dart';
import '../l10n/app_localizations.dart';
import '../native/onnx_gpu_probe.dart';
import '../render/ai_denoise.dart';
import '../theme.dart';
import 'dialog_chrome.dart';
import 'styled_dropdown.dart';

/// Sparingly used, not part of the app's usual monochrome palette — a
/// genuine caution color reads faster than another gray box for the one
/// thing in this dialog that's actually worth interrupting for (a GPU
/// that won't be used, when the whole point of the model choice was
/// speed).
const _warningColor = Color(0xFFE8A33D);

/// Default value for [NeuralEnhanceChoice.denoiseAmount]/the Amount
/// slider — 100%, the model's full-strength output. Was 50% under the
/// previous denoise model (NAFNet-SIDD), whose raw output tended to look
/// over-smoothed/"painted" on real photos; the model swap (2026-08-31,
/// item 35 follow-up — see `onnx_runtime.dart`'s [denoiseModelSpec] doc)
/// was specifically chosen for *not* having that problem in testing, and
/// this briefly defaulted to 100% on that basis. Reverted back to 50%
/// (2026-09-01, explicit user direction) to follow the same plain "new
/// toggle, balanced default" convention every other Amount slider in this
/// dialog uses (see [defaultRestoreDetailAmount]'s doc) rather than stay
/// the one exception. `editor_screen.dart` uses this same constant as the
/// fallback for any photo whose `_paramValues` doesn't have an amount
/// recorded yet (never turned Denoise on before, or predates this
/// slider) — see its own `_neuralDenoiseAmountKey` doc.
const defaultNeuralDenoiseAmount = 50;

/// Default value for [NeuralEnhanceChoice.restoreDetailAmount] — 50%, a
/// balanced starting blend, following the plain "new toggle, balanced
/// default" convention (2026-08-31, explicit user direction after testing
/// GaterV3 restore+sharpen — PENDING.md item 35 combo follow-up). See
/// [defaultNeuralDenoiseAmount]'s own doc — it now uses the same 50%.
const defaultRestoreDetailAmount = 50;

String _levelLabel(AppLocalizations l10n, AiDenoiseLevel? level) =>
    switch (level) {
      null => l10n.aiDenoiseLevelOff,
      AiDenoiseLevel.light => l10n.aiDenoiseLevelLight,
      AiDenoiseLevel.medium => l10n.aiDenoiseLevelMedium,
      AiDenoiseLevel.strong => l10n.aiDenoiseLevelStrong,
    };

/// Every choice offered by the Classic tab — `null` means "Off" (turn a
/// previously-applied level back off), listed first so switching it off is
/// never more than one tap away.
const _classicChoices = <AiDenoiseLevel?>[
  null,
  AiDenoiseLevel.light,
  AiDenoiseLevel.medium,
  AiDenoiseLevel.strong,
];

/// What [AiDenoiseDialog] resolves with — the two tabs are mutually
/// exclusive (a photo has either a classical level applied, or the neural
/// enhance pipeline applied, never both), so the result is one or the
/// other rather than a flat level like before item 13's neural pipeline
/// existed.
sealed class AiDenoiseChoice {
  const AiDenoiseChoice();
}

/// Off ([level] null) or one of the classical blur-based levels
/// (`lib/render/ai_denoise.dart`'s `applyAiDenoise` — a per-render
/// pipeline stage).
class ClassicDenoiseChoice extends AiDenoiseChoice {
  const ClassicDenoiseChoice(this.level);

  final AiDenoiseLevel? level;
}

/// The item-13 neural pipeline — a one-shot pre-process that replaces the
/// photo's edit source, not a per-render stage. [denoise]
/// and [upscale] (DIS 2x) are independent toggles rather than one
/// combined on/off switch, since either is a useful result on its own
/// (denoise a noisy JPEG without changing its resolution; upscale an
/// already-clean photo without paying for denoise it doesn't need).
/// [active] (both false) means "turn it back off" — checked by callers
/// instead of a stray null case.
class NeuralEnhanceChoice extends AiDenoiseChoice {
  const NeuralEnhanceChoice({
    required this.denoise,
    required this.upscale,
    this.denoiseAmount = defaultNeuralDenoiseAmount,
    this.rawDenoise = false,
    this.upscaleSharpnessAmount = 0,
    this.restoreDetail = false,
    this.restoreDetailAmount = defaultRestoreDetailAmount,
  });

  final bool denoise;
  final bool upscale;

  /// GaterV3 restore-then-sharpen (`gaterV3RestoreModelSpec`/
  /// `gaterV3SharpenModelSpec`) — a same-resolution detail pass,
  /// independent of [upscale] (found investigating item 35's "make it
  /// faster, no upscale needed" follow-up, 2026-08-31 — see PENDING.md).
  /// Unlike [upscaleSharpnessAmount], this pair is cheap enough
  /// (~2s combined on a 700x700 crop, faster than [denoise] itself) that
  /// it always runs once toggled on — [restoreDetailAmount] only controls
  /// the blend ratio, never whether the models load at all.
  final bool restoreDetail;

  /// 0-100 blend between [denoise]'s own output and the GaterV3 pair's
  /// (see `ai_enhance.dart`'s `enhanceImage` `detailAmount` doc). Only
  /// meaningful when [restoreDetail] is true.
  final int restoreDetailAmount;

  /// 0-100 blend between [upscale]'s own output (`upscaleModelSpec`/DIS,
  /// fast, fidelity-first) and Real-ESRGAN's (`realEsrganUpscaleModelSpec`
  /// — synthesizes more plausible detail; found investigating item 35's
  /// "papado" denoise complaint, 2026-08-31 — see PENDING.md). `0`
  /// (default) never even loads Real-ESRGAN, so it costs nothing; **any**
  /// value above 0 pays its full ~3.5-minutes-per-24MP-photo inference
  /// cost regardless of how small — the slider controls the *blend ratio*
  /// of an already-paid-for result, not a speed/quality gradient. Higher
  /// values also increase the chance of it slightly altering (not just
  /// sharpening) very small text/detail near the edge of resolution.
  /// Ignored when [upscale] is false.
  final int upscaleSharpnessAmount;

  /// PMRID raw-domain denoise (`pmrid_denoise.dart`) — runs on the
  /// sensor's own Bayer data before demosaic, unlike [denoise]
  /// (which runs after). Only ever true for a standard
  /// Bayer-CFA RAW file (see `libraw.dart`'s `RawMetadata.isBayerCfa`);
  /// mutually exclusive with [denoise] in the dialog UI (running both
  /// would just re-smooth pixels PMRID already cleaned) — enforced there,
  /// not here, so this class stays a plain data holder.
  final bool rawDenoise;

  /// 0-100 blend between the original and the denoise model's full-strength
  /// output (see `ai_enhance.dart`'s `enhanceImage` doc — the model has
  /// no strength control of its own, so this is a linear blend applied
  /// afterward). Only meaningful when [denoise] is true; ignored
  /// otherwise, and left at its default rather than made nullable so
  /// callers don't need a null-check for a value that never actually
  /// matters when unused.
  final int denoiseAmount;

  bool get active => denoise || upscale || rawDenoise || restoreDetail;
}

/// A paid, third-party cloud AI denoise call (the dialog's "Cloud AI" tab)
/// — a fundamentally different category from [NeuralEnhanceChoice]: that
/// pipeline runs on-device, for free, deterministically; this one uploads
/// the photo to a provider the user has their own API key/account with and
/// costs real money per call (see `cloud_denoise_cache.dart` for why the
/// result is cached aggressively). [provider] null (or [apiKey] empty)
/// means "off" — checked via [active], same pattern as
/// `NeuralEnhanceChoice`.
class CloudDenoiseChoice extends AiDenoiseChoice {
  const CloudDenoiseChoice({required this.provider, required this.apiKey});

  final CloudDenoiseProviderKind? provider;

  /// Transient — never persisted in `_paramValues`/the catalog file. The
  /// dialog reads this back out of `CloudDenoiseTokenStore` (secure
  /// storage) next time it opens; `editor_screen.dart` only remembers
  /// *which provider* was used, not the key itself.
  final String apiKey;

  bool get active => provider != null && apiKey.trim().isNotEmpty;
}

/// AI Denoise level/mode picker, opened from the toolbar's AI Denoise
/// button — three tabs, all mutually exclusive: **Classic** (the original
/// single-choice strength picker: each level already tuned to a good
/// noise/detail trade-off, so there's nothing else to set), **Enhance**
/// (item 13's on-device neural pipeline, a fundamentally different kind of
/// operation — it can change the photo's resolution and has independent
/// Denoise/Upscale toggles instead of strength levels, hence its own tab
/// rather than folded into Classic's four chips), and **Cloud AI** (a
/// paid, third-party call the user brings their own API key to — see
/// [CloudDenoiseChoice]). Resolves with an [AiDenoiseChoice], or with a
/// plain `null` if the dialog was dismissed without a choice.
class AiDenoiseDialog extends StatefulWidget {
  const AiDenoiseDialog({
    super.key,
    required this.initialLevel,
    required this.neuralDenoise,
    required this.neuralUpscale,
    this.neuralDenoiseAmount = defaultNeuralDenoiseAmount,
    this.neuralRawDenoise = false,
    this.rawDenoiseAvailable = false,
    this.cloudProvider,
    this.upscaleSharpnessAmount = 0,
    this.neuralRestoreDetail = false,
    this.restoreDetailAmount = defaultRestoreDetailAmount,
  });

  /// The classical level already applied to the current photo, if any —
  /// preselected so reopening the dialog shows what's active rather than
  /// resetting to a default.
  final AiDenoiseLevel? initialLevel;

  /// Whether the neural pipeline's denoise/upscale passes are already
  /// applied to the current photo — same preselection reasoning as
  /// [initialLevel].
  final bool neuralDenoise;
  final bool neuralUpscale;

  /// See [NeuralEnhanceChoice.denoiseAmount].
  final int neuralDenoiseAmount;

  /// See [NeuralEnhanceChoice.rawDenoise].
  final bool neuralRawDenoise;

  /// See [NeuralEnhanceChoice.upscaleSharpnessAmount].
  final int upscaleSharpnessAmount;

  /// See [NeuralEnhanceChoice.restoreDetail].
  final bool neuralRestoreDetail;

  /// See [NeuralEnhanceChoice.restoreDetailAmount].
  final int restoreDetailAmount;

  /// Whether the current photo is a standard Bayer-CFA RAW file — the raw
  /// denoise toggle is shown disabled (with an explanatory caption) when
  /// this is false, since PMRID can't process X-Trans/Foveon sensors or a
  /// non-RAW format at all (see `libraw.dart`'s `RawMetadata.isBayerCfa`).
  final bool rawDenoiseAvailable;

  /// The cloud provider already applied to the current photo, if any —
  /// same preselection reasoning as [initialLevel]. The API key itself is
  /// never passed in here (see [CloudDenoiseChoice.apiKey]'s doc) — the
  /// dialog reads it back from secure storage on its own once a provider
  /// is selected.
  final CloudDenoiseProviderKind? cloudProvider;

  @override
  State<AiDenoiseDialog> createState() => _AiDenoiseDialogState();
}

class _AiDenoiseDialogState extends State<AiDenoiseDialog>
    with SingleTickerProviderStateMixin {
  late AiDenoiseLevel? _level = widget.initialLevel;
  late bool _neuralDenoise = widget.neuralDenoise;
  late bool _neuralUpscale = widget.neuralUpscale;
  late bool _neuralRawDenoise = widget.neuralRawDenoise;
  late int _denoiseAmount = widget.neuralDenoiseAmount;
  late int _upscaleSharpnessAmount = widget.upscaleSharpnessAmount;
  late bool _neuralRestoreDetail = widget.neuralRestoreDetail;
  late int _restoreDetailAmount = widget.restoreDetailAmount;
  late CloudDenoiseProviderKind? _cloudProvider = widget.cloudProvider;
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.cloudProvider != null
        ? 2
        : (widget.neuralDenoise ||
              widget.neuralUpscale ||
              widget.neuralRawDenoise ||
              widget.neuralRestoreDetail)
        ? 1
        : 0,
  );

  /// null while the probe hasn't resolved yet — the Enhance tab shows
  /// nothing extra until then rather than guessing. `false` is exactly
  /// the case the warning below exists for.
  bool? _gpuAvailable;

  @override
  void initState() {
    super.initState();
    // Drives the IndexedStack below off the controller's current tab —
    // there's no TabBarView/PageView here (see the `content` comment), so
    // nothing else rebuilds this widget when a tab is tapped.
    _tabController.addListener(() => setState(() {}));
    unawaited(_probeGpu());
    if (widget.cloudProvider != null) {
      unawaited(_loadStoredToken(widget.cloudProvider!));
    }
  }

  /// Cached after the first probe (see `probeAiEnhanceGpuSupport`'s own
  /// doc) — creating a real ONNX session costs ~1-2s either way, so this
  /// dialog only pays that once per app run, not once per open.
  Future<void> _probeGpu() async {
    final available = await probeAiEnhanceGpuSupport();
    if (mounted) {
      setState(() => _gpuAvailable = available);
    }
  }

  /// Prefills the token field from secure storage — never from
  /// `_paramValues`/the catalog (see `CloudDenoiseChoice.apiKey`'s doc),
  /// so switching providers in the dropdown re-reads whatever was last
  /// saved for *that* provider, if anything.
  Future<void> _loadStoredToken(CloudDenoiseProviderKind provider) async {
    final token = await CloudDenoiseTokenStore.read(provider);
    if (mounted && _cloudProvider == provider) {
      _tokenController.text = token ?? '';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// The three tabs are mutually exclusive — picking a Classic level turns
  /// off both the Enhance toggles and the cloud provider, and vice versa
  /// for the other two, so whichever tab the user isn't looking at always
  /// agrees with what's about to actually be applied (no denoise pipeline
  /// ever stacks with another on the same photo).
  void _pickClassic(AiDenoiseLevel? level) {
    setState(() {
      _level = level;
      _neuralDenoise = false;
      _neuralUpscale = false;
      _neuralRawDenoise = false;
      _neuralRestoreDetail = false;
      _cloudProvider = null;
    });
  }

  void _setNeuralDenoise(bool value) {
    setState(() {
      _neuralDenoise = value;
      if (value) {
        _level = null;
        // Mutually exclusive with raw denoise — running both would just
        // re-smooth pixels PMRID already cleaned.
        _neuralRawDenoise = false;
        _cloudProvider = null;
      }
    });
  }

  void _setNeuralUpscale(bool value) {
    setState(() {
      _neuralUpscale = value;
      if (value) {
        _level = null;
        _cloudProvider = null;
      }
    });
  }

  void _setUpscaleSharpnessAmount(int value) {
    setState(() => _upscaleSharpnessAmount = value);
  }

  void _setNeuralRestoreDetail(bool value) {
    setState(() {
      _neuralRestoreDetail = value;
      if (value) {
        _level = null;
        _cloudProvider = null;
      }
    });
  }

  void _setRestoreDetailAmount(int value) {
    setState(() => _restoreDetailAmount = value);
  }

  void _setNeuralRawDenoise(bool value) {
    setState(() {
      _neuralRawDenoise = value;
      if (value) {
        _level = null;
        _neuralDenoise = false;
        _cloudProvider = null;
      }
    });
  }

  void _setCloudProvider(CloudDenoiseProviderKind? provider) {
    setState(() {
      _cloudProvider = provider;
      _tokenController.text = '';
      if (provider != null) {
        _level = null;
        _neuralDenoise = false;
        _neuralUpscale = false;
        _neuralRawDenoise = false;
        _neuralRestoreDetail = false;
        unawaited(_loadStoredToken(provider));
      }
    });
  }

  AiDenoiseChoice get _currentChoice {
    if (_cloudProvider != null) {
      return CloudDenoiseChoice(
        provider: _cloudProvider,
        apiKey: _tokenController.text.trim(),
      );
    }
    if (_neuralDenoise ||
        _neuralUpscale ||
        _neuralRawDenoise ||
        _neuralRestoreDetail) {
      return NeuralEnhanceChoice(
        denoise: _neuralDenoise,
        upscale: _neuralUpscale,
        denoiseAmount: _denoiseAmount,
        rawDenoise: _neuralRawDenoise,
        upscaleSharpnessAmount: _upscaleSharpnessAmount,
        restoreDetail: _neuralRestoreDetail,
        restoreDetailAmount: _restoreDetailAmount,
      );
    }
    return ClassicDenoiseChoice(_level);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: DarkmoonColors.dialogBackground,
      shape: dialogShape,
      title: Text(
        l10n.aiDenoiseDialogTitle,
        style: const TextStyle(color: DarkmoonColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        // No fixed height: Classic's/Enhance's/Cloud AI's content are very
        // different lengths (Cloud AI, once a generative provider's
        // warning banner joins the always-on disclosure, is the tallest —
        // tall enough to overflow a real dialog on a modest window height,
        // confirmed by a widget test), and a hard-coded height either
        // overflows the shorter tabs into a scroll they don't need or
        // clips the taller one. An IndexedStack (not TabBarView — that
        // needs a bounded height for its PageView, which is exactly what
        // we're avoiding) sizes itself to its biggest child; wrapping it in
        // Flexible+SingleChildScrollView lets the dialog grow to fit
        // whichever tab is tallest UP TO whatever height AlertDialog
        // actually has available, scrolling internally instead of
        // overflowing beyond that.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabController,
              labelColor: DarkmoonColors.textPrimary,
              unselectedLabelColor: DarkmoonColors.textMuted,
              indicatorColor: DarkmoonColors.accent,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: DarkmoonColors.divider,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12.5),
              tabs: [
                Tab(text: l10n.aiDenoiseTabClassic),
                Tab(text: l10n.aiDenoiseTabEnhance),
                Tab(text: l10n.aiDenoiseTabCloud),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: IndexedStack(
                  index: _tabController.index,
                  alignment: Alignment.topLeft,
                  children: [
                    _buildClassicTab(l10n),
                    _buildEnhanceTab(l10n),
                    _buildCloudTab(l10n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentChoice),
          child: Text(l10n.aiDenoiseApplyButton),
        ),
      ],
    );
  }

  Widget _buildClassicTab(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiDenoiseDialogMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final choice in _classicChoices) ...[
              if (choice != _classicChoices.first) const SizedBox(width: 8),
              Expanded(
                child: _LevelChip(
                  label: _levelLabel(l10n, choice),
                  selected:
                      !_neuralDenoise &&
                      !_neuralUpscale &&
                      !_neuralRawDenoise &&
                      _cloudProvider == null &&
                      _level == choice,
                  onTap: () => _pickClassic(choice),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEnhanceTab(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiDenoiseEnhanceMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // Told up front, before the user commits to running it — the
        // same fact `editor_screen.dart`'s CPU-fallback SnackBar reports,
        // just moved earlier so it can actually change the user's mind
        // instead of only explaining a slow wait after it's started.
        // Silent while `_gpuAvailable` is still null (mid-probe) or true
        // (nothing worth interrupting for).
        if (_gpuAvailable == false) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _warningColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _warningColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 14,
                  color: _warningColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.aiDenoiseEnhanceGpuIncompatibleWarning,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: DarkmoonColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        // Independent toggles, not a single on/off switch — denoising a
        // noisy JPEG without upscaling it, or upscaling an already-clean
        // photo without paying for denoise it doesn't need, are both
        // useful on their own, not just as a combined "Enhance" pass.
        // Stacked (not side by side) so each has room for a longer label.
        // Plain Switch + Text rather than SwitchListTile — ListTile's own
        // minimum height pushed the dialog past its available space by a
        // few pixels (an overflow only a widget test surfaces; visually
        // negligible on a real screen, but still real).
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceDenoiseLabel,
          value: _neuralDenoise,
          onChanged: _setNeuralDenoise,
        ),
        // Only shown once Denoise is on — an amount for a pass that isn't
        // even running has nothing to control. The model itself has no
        // strength input (see NeuralEnhanceChoice.denoiseAmount's doc);
        // this blends its full-strength output back toward the original.
        if (_neuralDenoise) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiDenoiseEnhanceAmountLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DarkmoonColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$_denoiseAmount%',
                style: const TextStyle(
                  fontSize: 12,
                  color: DarkmoonColors.textMuted,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(
              context,
            ).copyWith(trackShape: const RectangularSliderTrackShape()),
            child: Slider(
              min: 0,
              max: 100,
              divisions: 100,
              value: _denoiseAmount.toDouble(),
              onChanged: (v) => setState(() => _denoiseAmount = v.round()),
            ),
          ),
        ],
        const SizedBox(height: 4),
        // GaterV3 restore+sharpen — independent of Upscale (unlike the
        // Sharpness slider below, this stays same-resolution), found
        // investigating item 35's "make it faster, no upscale needed"
        // follow-up. Cheap enough to always run once toggled on — the
        // Amount slider only controls blend ratio, defaulting to a
        // balanced 50% since (unlike Denoise's 100%) there's no evidence
        // yet that full strength is always the right call here.
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceRestoreDetailLabel,
          value: _neuralRestoreDetail,
          onChanged: _setNeuralRestoreDetail,
        ),
        if (_neuralRestoreDetail) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiDenoiseEnhanceAmountLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DarkmoonColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$_restoreDetailAmount%',
                style: const TextStyle(
                  fontSize: 12,
                  color: DarkmoonColors.textMuted,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(
              context,
            ).copyWith(trackShape: const RectangularSliderTrackShape()),
            child: Slider(
              min: 0,
              max: 100,
              divisions: 100,
              value: _restoreDetailAmount.toDouble(),
              onChanged: (v) => _setRestoreDetailAmount(v.round()),
            ),
          ),
        ],
        const SizedBox(height: 4),
        // Upscale toggle: was hidden for a while (the previous Real-ESRGAN
        // model's results weren't good enough) — re-enabled once
        // upscaleModelSpec pointed at DIS 2x instead (see onnx_runtime.dart),
        // a much lighter/faster model. Real-ESRGAN itself is back too, now
        // blended in via the Sharpness slider below instead of being the
        // default (see NeuralEnhanceChoice.upscaleSharpnessAmount's doc).
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceUpscaleLabel,
          value: _neuralUpscale,
          onChanged: _setNeuralUpscale,
        ),
        // Only shown once Upscale is on, same reasoning as the denoise
        // Amount slider above — a blend ratio for a pass that isn't even
        // running has nothing to control.
        if (_neuralUpscale) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiDenoiseEnhanceSharpnessLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DarkmoonColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$_upscaleSharpnessAmount%',
                style: const TextStyle(
                  fontSize: 12,
                  color: DarkmoonColors.textMuted,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(
              context,
            ).copyWith(trackShape: const RectangularSliderTrackShape()),
            child: Slider(
              min: 0,
              max: 100,
              divisions: 100,
              value: _upscaleSharpnessAmount.toDouble(),
              onChanged: (v) => _setUpscaleSharpnessAmount(v.round()),
            ),
          ),
          // Not a speed gradient — see the slider's own field doc. Anything
          // above 0% pays Real-ESRGAN's full ~3.5-min-per-24MP-photo cost,
          // so the caption stays up front about that regardless of exactly
          // how far the slider is dragged, not just once it crosses some
          // threshold.
          if (_upscaleSharpnessAmount > 0) ...[
            const SizedBox(height: 2),
            Text(
              l10n.aiDenoiseEnhanceSharpnessCaption,
              style: const TextStyle(
                fontSize: 11,
                color: DarkmoonColors.textMuted,
              ),
            ),
          ],
        ],
        const SizedBox(height: 4),
        // Runs on the sensor's own Bayer data before demosaic (see
        // NeuralEnhanceChoice.rawDenoise's doc) — only possible for a
        // standard Bayer RAW, so the toggle is shown disabled with an
        // explanatory caption rather than hidden outright when the current
        // photo can't use it (X-Trans, Foveon/monochrome, or a non-RAW
        // format), so the user learns why it's missing instead of just not
        // finding it.
        _ToggleRow(
          label: l10n.aiDenoiseEnhanceRawDenoiseLabel,
          value: _neuralRawDenoise,
          onChanged: widget.rawDenoiseAvailable ? _setNeuralRawDenoise : null,
        ),
        if (!widget.rawDenoiseAvailable) ...[
          const SizedBox(height: 2),
          Text(
            l10n.aiDenoiseEnhanceRawDenoiseUnavailableCaption,
            style: const TextStyle(
              fontSize: 11,
              color: DarkmoonColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCloudTab(AppLocalizations l10n) {
    final provider = _cloudProvider;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiDenoiseCloudMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        StyledDropdown<CloudDenoiseProviderKind?>(
          label: l10n.aiDenoiseCloudProviderLabel,
          value: provider,
          items: [
            StyledDropdownItem(
              value: null,
              label: l10n.aiDenoiseCloudProviderOff,
            ),
            StyledDropdownItem(
              value: CloudDenoiseProviderKind.topaz,
              label: l10n.aiDenoiseCloudProviderTopaz,
            ),
            StyledDropdownItem(
              value: CloudDenoiseProviderKind.openai,
              label: l10n.aiDenoiseCloudProviderOpenAi,
            ),
            StyledDropdownItem(
              value: CloudDenoiseProviderKind.gemini,
              label: l10n.aiDenoiseCloudProviderGemini,
            ),
          ],
          onChanged: _setCloudProvider,
        ),
        if (provider != null) ...[
          const SizedBox(height: 10),
          Text(
            l10n.aiDenoiseCloudTokenLabel,
            style: const TextStyle(
              fontSize: 12,
              color: DarkmoonColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            style: const TextStyle(
              color: DarkmoonColors.textPrimary,
              fontSize: 12.5,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.aiDenoiseCloudTokenHint,
              hintStyle: const TextStyle(
                color: DarkmoonColors.textMuted,
                fontSize: 12,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              filled: true,
              fillColor: DarkmoonColors.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DarkmoonColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DarkmoonColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DarkmoonColors.accent),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 16,
                  color: DarkmoonColors.textMuted,
                ),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Cost/privacy disclosure — always shown once a provider is
          // picked, not just for the generative ones below: every one of
          // these uploads the photo to a third party and costs real money,
          // Topaz included.
          _CloudInfoBanner(
            icon: CupertinoIcons.info_circle_fill,
            color: DarkmoonColors.textMuted,
            text: l10n.aiDenoiseCloudDisclosure,
          ),
          if (provider.isGenerative) ...[
            const SizedBox(height: 8),
            _CloudInfoBanner(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: _warningColor,
              text: l10n.aiDenoiseCloudGenerativeWarning,
            ),
          ],
        ],
      ],
    );
  }
}

/// Small text-plus-icon banner used by the Cloud AI tab's disclosure/
/// warning messages — same visual template as the Enhance tab's inline GPU
/// warning, factored out here since the Cloud tab needs two of these
/// (always-shown disclosure, conditional generative-risk warning) rather
/// than that tab's single one-off case.
class _CloudInfoBanner extends StatelessWidget {
  const _CloudInfoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: DarkmoonColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;

  /// Null disables the row entirely (used for a toggle the current photo
  /// can't support at all, e.g. raw denoise on a non-Bayer file) — Switch
  /// already renders a muted, non-interactive look for `onChanged: null`,
  /// so this only needs to also stop the row's own tap-anywhere handler.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    // The whole row toggles on tap (not just the Switch itself), same
    // "tap anywhere in the row" convention SwitchListTile gives elsewhere
    // in this app (e.g. settings_dialog.dart) — GestureDetector here
    // instead, since SwitchListTile's own minimum height overflowed this
    // dialog by a few pixels (see _buildEnhanceTab's comment).
    final enabled = onChanged != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled
                    ? DarkmoonColors.textPrimary
                    : DarkmoonColors.textMuted,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? DarkmoonColors.accent : DarkmoonColors.canvas,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? DarkmoonColors.accent : DarkmoonColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? DarkmoonColors.background
                : DarkmoonColors.textSecondary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
