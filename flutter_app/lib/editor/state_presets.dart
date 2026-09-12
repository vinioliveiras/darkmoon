// Presets: loading, applying, saving, renaming, deleting, import and
// export.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorPresets on _EditorScreenState {
  Future<void> _loadPresetsState() async {
    final presets = await loadPresets();
    if (!mounted) {
      return;
    }
    _rebuild(() => _presets = presets);
  }

  /// Applies [preset]'s slider values and curves to the selected photo, at
  /// their full stored strength — like every other adjustment, this only
  /// touches the global ("Image") layer, never the active mask, matching
  /// how real Meridian presets don't carry local adjustments either.
  ///
  /// Unlike this app's previous design, applying a preset no longer blends
  /// by the Amount slider under the preset list — [_globalEditAmountKey]
  /// is now a separate, persistent render-time multiplier over the
  /// *entire* current edit (this preset's values *and* whatever the
  /// sliders get manually adjusted to afterward), rather than something
  /// that rewrites `_paramValues` itself on every drag. See
  /// [withGlobalEditAmountApplied]'s doc for why: the old design made
  /// dragging Amount visibly overwrite the right-hand sliders (confusing,
  /// and silently discarded any manual tweaks made since the preset was
  /// applied) and stopped doing anything at all once a manual edit had
  /// cleared [_appliedPresetId]. The new design fixes both — Amount keeps
  /// working regardless of what's been manually tweaked since, and never
  /// mutates a single slider's stored value.
  void _applyPreset(Preset preset) {
    if (_selectedIndex == null) {
      return;
    }
    // Only the continuous slider keys get overridden by the preset.
    // Everything else in the flat map — the per-section enable toggles
    // (_categoryEnabled_*), the White Balance mode, preserve-brightness,
    // [_globalEditAmountKey] itself — is a discrete/independent flag the
    // preset doesn't touch unless it explicitly sets it.
    final defaults = _defaultParamValues();
    final sliderKeys = defaults.keys.toSet()
      ..remove('Temperature')
      ..remove('Tint')
      // Amount is a separate, persistent setting (see
      // withGlobalEditAmountApplied) — applying a preset never resets it.
      ..remove(_globalEditAmountKey)
      // Same reasoning as Amount, real bug fixed 2026-09-01: an XMP-derived
      // preset never carries this key (it's darkmoon-specific), so the
      // generic "preset doesn't specify it -> use the flat _SliderSpec
      // default (20)" fallback below was resetting Contrast to 20 on
      // every preset apply regardless of which ColorProfileMode was
      // active — wrong for Vivid (baseline 0). Handled explicitly below
      // instead, against the *current* mode's own baseline.
      ..remove('ColorProfileAmount');
    final newValues = <String, double>{..._paramValues};
    for (final key in sliderKeys) {
      newValues[key] = preset.values[key] ?? defaults[key] ?? 0;
    }
    newValues['ColorProfileAmount'] =
        preset.values['ColorProfileAmount'] ??
        colorProfileModeOf(_paramValues).contrastBaseline;
    for (final entry in preset.values.entries) {
      if (!sliderKeys.contains(entry.key) &&
          entry.key != 'Temperature' &&
          entry.key != 'Tint') {
        newValues[entry.key] = entry.value;
      }
    }
    // White Balance:
    //  - preset defines a real WB -> apply it (mode Custom, or the
    //    preset's own mode if it stored one);
    //  - preset defines none      -> reset to the photo's As Shot.
    // "Defines a real WB" ignores a bare 5500/0 with no mode key: that's
    // the old fixed neutral every pre-feature preset carries incidentally,
    // not an intended white-balance edit.
    final asShot = _asShotFor(_files[_selectedIndex!].path);
    final presetTemp = preset.values['Temperature'];
    final presetTint = preset.values['Tint'];
    final presetMode = preset.values[_wbModeKey];
    final presetDefinesWb =
        (presetTemp != null && presetTemp != wbDefaultKelvin) ||
        (presetTint != null && presetTint != wbDefaultTint) ||
        (presetMode != null && presetMode != WbMode.asShot.index.toDouble());
    if (presetDefinesWb) {
      newValues['Temperature'] = presetTemp ?? asShot.kelvin;
      newValues['Tint'] = presetTint ?? asShot.tint;
      newValues[_wbModeKey] = presetMode ?? WbMode.custom.index.toDouble();
    } else {
      newValues['Temperature'] = asShot.kelvin;
      newValues['Tint'] = asShot.tint;
      newValues[_wbModeKey] = WbMode.asShot.index.toDouble();
    }
    // A preset that carries masks replaces the stack, as Meridian does;
    // one without leaves the photo's own masks alone. Meridian's are
    // converted for this photo's aspect (see preset_masks.dart); ours are
    // re-minted so two applies never share an id.
    List<MaskLayer>? presetMasks;
    if (preset.hasMasks) {
      final path = _files[_selectedIndex!].path;
      final source = _editSources[path]?.live;
      final aspect = source == null || source.height == 0
          ? 1.5
          : source.width / source.height;
      var serial = 0;
      String newId() =>
          'mask_${DateTime.now().microsecondsSinceEpoch}_${serial++}';
      presetMasks = [
        for (final mask in preset.masks)
          MaskLayer(
            id: newId(),
            name: mask.name,
            type: mask.type,
            linear: mask.linear,
            radial: mask.radial,
            brush: mask.brush,
            colorRange: mask.colorRange,
            luminance: mask.luminance,
            subject: mask.subject,
            depth: mask.depth,
            enabled: mask.enabled,
            inverted: mask.inverted,
            opacity: mask.opacity,
            values: mask.values,
            curves: mask.curves,
          ),
        ...maskLayersForImage(
          preset.meridianMasks,
          aspect: aspect,
          newId: newId,
        ),
      ];
    }
    _rebuild(() {
      _paramValues = newValues;
      _currentCurves = preset.curves;
      _appliedPresetId = preset.id;
      if (presetMasks != null) {
        _currentMasks = presetMasks;
      }
    });
    _pushHistory();
    _scheduleRender(live: false);
    unawaited(_flushCurrentEdits());
    // Preset attributes this app can't render yet (see
    // Preset.unsupportedAttributes / preset_xmp.dart) are silently
    // ignored — no user-facing warning. The gap is tracked in the repo's
    // PENDING.md; the goal is full preset compatibility.
  }

  /// Whether [preset] is the one currently applied to the selected photo.
  /// Tracked via [_appliedPresetId] which is set on apply and cleared on
  /// any manual edit, photo switch, reset, or file reload — so the preset
  /// stays highlighted even when the user changes the global Amount
  /// slider (see [_globalEditAmountKey]), and only clears when they make
  /// a deliberate change.
  bool _matchesAppliedPreset(Preset preset) {
    return _appliedPresetId == preset.id;
  }

  Future<void> _saveCurrentAsPreset() async {
    if (_selectedIndex == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final name = await showTextPromptDialog(
      context,
      title: l10n.presetSaveNewTitle,
    );
    if (name == null || !mounted) {
      return;
    }
    final draft = Preset(
      id: 'preset_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      // _catalogParams() drops Temperature/Tint while on "As Shot", so a
      // preset saved without a deliberate WB doesn't force one on other
      // photos.
      values: _catalogParams(),
      curves: _currentCurves,
      // The mask stack goes with the preset (in our own geometry, so it
      // fits photos of the same shape best), the way Meridian's presets
      // can carry masks.
      masks: _currentMasks,
    );
    final saved = await savePresetToFile(draft);
    if (!mounted) {
      return;
    }
    _rebuild(() => _presets = _sortPresets([..._presets, saved]));
  }

  List<Preset> _sortPresets(List<Preset> presets) =>
      presets
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> _renamePreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showTextPromptDialog(
      context,
      title: l10n.presetRenameTitle,
      initialValue: preset.name,
    );
    if (name == null || !mounted) {
      return;
    }
    final renamed = await renamePresetFile(preset, name);
    if (!mounted) {
      return;
    }
    _rebuild(() {
      _presets = _sortPresets([
        for (final p in _presets)
          if (p.id == preset.id) renamed else p,
      ]);
      // The marker keys off the preset id (its file path), which the
      // rename changed — carry it over so the mark doesn't drop.
      if (_appliedPresetId == preset.id) {
        _appliedPresetId = renamed.id;
      }
    });
  }

  Future<void> _deletePreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
        title: Text(l10n.confirmClearTitle),
        content: Text(l10n.presetDeleteConfirmMessage(preset.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.presetDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await deletePresetFile(preset);
    if (!mounted) {
      return;
    }
    _rebuild(() {
      _presets = [
        for (final p in _presets)
          if (p.id != preset.id) p,
      ];
    });
  }

  Future<void> _deletePresets(List<Preset> presets) async {
    if (presets.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
        title: Text(l10n.confirmClearTitle),
        content: Text(l10n.presetDeleteManyConfirmMessage(presets.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.presetDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    for (final preset in presets) {
      await deletePresetFile(preset);
    }
    if (!mounted) {
      return;
    }
    final ids = {for (final preset in presets) preset.id};
    _rebuild(() {
      _presets = [
        for (final p in _presets)
          if (!ids.contains(p.id)) p,
      ];
    });
  }

  Future<void> _exportPreset(Preset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.presetExportDialogTitle,
      fileName: '${preset.name}.xmp',
      type: FileType.custom,
      allowedExtensions: ['xmp'],
    );
    if (destPath == null) {
      return;
    }
    await File(destPath).writeAsString(xmpFromPreset(preset));
  }

  /// Exports the multi-selected presets as a single `.zip` of `.xmp` files
  /// — the bulk counterpart to [_exportPreset], reachable from the Presets
  /// panel's selection-mode header.
  Future<void> _exportPresets(List<Preset> presets) async {
    if (presets.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.presetExportManyDialogTitle,
      fileName: 'darkmoon-presets.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (destPath == null) {
      return;
    }
    await File(destPath).writeAsBytes(presetsToZipBytes(presets));
  }

  /// Imports one or more `.xmp` presets, or `.zip` bundles of them (how
  /// Meridian exports multiple presets at once) — each zip is unpacked
  /// and every `.xmp` inside it imported the same way a standalone file
  /// would be.
  Future<void> _importPresets() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.presetImportDialogTitle,
      type: FileType.custom,
      allowedExtensions: [
        'xmp',
        'zip',
        // Other editors' presets — see preset_formats.dart.
        ...foreignPresetExtensions,
        'costylepack',
      ],
      allowMultiple: true,
    );
    if (result == null) {
      return;
    }
    final imported = <Preset>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) {
        continue;
      }
      final lower = path.toLowerCase();
      if (lower.endsWith('.zip') || lower.endsWith('.costylepack')) {
        imported.addAll(await importPresetsFromZipFile(path));
        continue;
      }
      final preset = await importPresetFromFile(path);
      if (preset != null) {
        imported.add(preset);
      }
    }
    if (imported.isEmpty || !mounted) {
      return;
    }
    _rebuild(() => _presets = _sortPresets([..._presets, ...imported]));
  }
}
