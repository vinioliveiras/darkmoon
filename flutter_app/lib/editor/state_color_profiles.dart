// Colour profiles: the user profile library, its editor dialog and
// the profile eyedropper.
//
// A `part` of editor_screen.dart holding methods of _EditorScreenState,
// as an extension: same library, same private scope, fields stay on the
// State. `setState` is protected and an extension is not a subclass, so
// these go through the State's `_rebuild`. Split 2026-09-10 for navigation.
part of '../editor_screen.dart';

extension _EditorColorProfiles on _EditorScreenState {
  /// The Amount slider under the preset list — see
  /// [_globalEditAmountKey]/[withGlobalEditAmountApplied]. Deliberately
  /// NOT [_onParamChanged]/[_onParamChangeEnd]: those clear
  /// [_appliedPresetId] on every change (a manual slider edit un-links
  /// the preset), but Amount isn't a manual edit to any one slider — the
  /// preset should stay highlighted in the list while its overall
  /// strength is being tuned, exactly like the old design already
  /// promised (see [_matchesAppliedPreset]'s doc).
  /// The user profile currently selected, if the selection is one at all.
  ColorProfile? get _selectedUserColorProfile =>
      colorProfileModeOf(_paramValues) == ColorProfileMode.custom
      ? _userColorProfiles[customProfileIdOf(_paramValues)]
      : null;

  /// Re-opens the selected profile for editing. Keeps its id, so every
  /// photo already using it follows the edit rather than being orphaned.
  Future<void> _editSelectedColorProfile() async {
    final profile = _selectedUserColorProfile;
    if (profile != null) {
      await _openColorProfileEditor(initial: profile);
    }
  }

  /// Copies the selected profile under a new id, so editing the copy
  /// cannot disturb photos using the original.
  Future<void> _duplicateSelectedColorProfile() async {
    final profile = _selectedUserColorProfile;
    if (profile == null) {
      return;
    }
    final copy = await saveUserColorProfile(
      profile.withId(newColorProfileId()).withName('${profile.name} (2)'),
    );
    await _loadUserColorProfiles();
    if (mounted) {
      _applyColorProfileChoice(copy.id);
    }
  }

  Future<void> _renameSelectedColorProfile() async {
    final profile = _selectedUserColorProfile;
    if (profile == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final name = await showTextPromptDialog(
      context,
      title: l10n.colorProfileRenameTitle,
      initialValue: profile.name,
    );
    if (name == null || name.trim().isEmpty || !mounted) {
      return;
    }
    // The id is untouched: renaming must not detach the photos using it.
    await saveUserColorProfile(profile.withName(name.trim()));
    await _loadUserColorProfiles();
  }

  Future<void> _exportSelectedColorProfile() async {
    final profile = _selectedUserColorProfile;
    if (profile == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final destPath = await FilePicker.saveFile(
      dialogTitle: l10n.colorProfileExportDialogTitle,
      fileName: '${profile.name}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (destPath == null) {
      return;
    }
    await exportColorProfile(profile, destPath);
  }

  Future<void> _deleteSelectedColorProfile() async {
    final profile = _selectedUserColorProfile;
    if (profile == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DarkmoonColors.dialogBackground,
        shape: dialogShape,
        title: Text(l10n.colorProfileDeleteTitle),
        content: Text(l10n.colorProfileDeleteMessage(profile.name)),
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
    await deleteUserColorProfile(profile.id);
    await _loadUserColorProfiles();
    if (!mounted) {
      return;
    }
    // Back to Default for *this* photo, since its profile genuinely no
    // longer exists. Other photos still referencing it keep the dangling
    // reference and show the missing-profile warning instead — deleting a
    // profile must not silently rewrite every photo that used it.
    _applyColorProfileMode(ColorProfileMode.darkmoonDefault);
  }

  Future<void> _importColorProfile() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.colorProfileImportDialogTitle,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    try {
      final imported = await importColorProfile(path);
      await _loadUserColorProfiles();
      if (mounted) {
        _applyColorProfileChoice(imported.id);
      }
    } catch (_) {
      if (mounted) {
        _showTransientStatus(l10n.colorProfileImportFailed);
      }
    }
  }

  /// Opens the colour profile editor, previewing on the current photo.
  Future<void> _openColorProfileEditor({
    ColorProfile? initial,
    double? highlightHue,
  }) async {
    // Not awaited: the neutral render this reads (or makes) took the
    // best part of a second on a large RAW, and the dialog sat closed
    // for all of it (user's report, 2026-09-11). It opens on the chart
    // now and the photo joins it when ready.
    final photoPreview = _profilePreviewSource();
    final existingNames = _userColorProfiles.values
        .map((profile) => profile.name)
        .toSet();
    // showAnimatedDialog with its default dimming barrier, exactly like
    // Settings — user's call, 2026-09-07. The transparent barrier this had
    // before existed so the canvas could serve as the live preview; the
    // dialog carries its own preview now, so the canvas no longer has to.
    final result = await showAnimatedDialog<ColorProfileEditorResult>(
      context: context,
      builder: (context) => ColorProfileEditorDialog(
        initial:
            initial ??
            ColorProfile(
              tone: identityColorProfile.tone,
              hueShift: List<double>.of(identityColorProfile.hueShift),
              satMul: List<double>.of(identityColorProfile.satMul),
              lumMul: List<double>.of(identityColorProfile.lumMul),
              id: newColorProfileId(),
            ),
        highlightHue: highlightHue,
        photoPreview: photoPreview,
        existingNames: existingNames,
        // Where the dialog's own preview controls start. It moves them
        // from there and writes nothing back — see its doc.
        strength: _paramValues[_globalEditAmountKey] ?? 100.0,
        contrast: _paramValues['ColorProfileAmount'] ?? calBaseContrast,
        // No render on the live stream any more. The dialog's own
        // preview is what the user is watching, and the canvas behind a
        // dimmed barrier is not worth a GPU pass per frame of a drag.
        //
        // Nor is the draft recorded any more (2026-09-09, user's report):
        // it used to outrank the photo's own profile in
        // [_effectiveColorProfile], so authoring one edited the photo
        // behind the dialog as a side effect. The dialog's previews are
        // built from the draft directly and are the only thing it changes.
        onDraftChanged: (_) {},
        onDraftSettled: (_) {},
      ),
    );

    if (!mounted) {
      return;
    }
    if (result == null) {
      // Cancelled. Nothing to undo — the photo was never touched.
      return;
    }

    if (result.pickHue) {
      // Arm the canvas and wait. The draft is held rather than saved: the
      // user has not agreed to create anything yet, they asked a question
      // about a colour.
      _rebuild(() {
        _profileHueEyedropperActive = true;
        _pendingProfileDraft = result.profile;
      });
      _scheduleRender(live: false);
      return;
    }

    final stored = await saveUserColorProfile(result.profile);
    await _loadUserColorProfiles();
    if (!mounted) {
      return;
    }
    // Select what was just built. Doing this only after the save means a
    // failed write leaves the photo pointing at something that exists.
    _applyColorProfileChoice(stored.id);
  }

  /// What the COLOR PROFILE dropdown should currently show — a
  /// [ColorProfileMode] index for a built-in, a [ColorProfile.id] for one
  /// of the user's. See [reservedColorProfileIds].
  int get _colorProfileChoice {
    final mode = colorProfileModeOf(_paramValues);
    return mode == ColorProfileMode.custom
        ? customProfileIdOf(_paramValues)
        : mode.index;
  }

  /// The dropdown's single entry point, mapping that int back to either a
  /// built-in mode or a user profile.
  void _applyColorProfileChoice(int choice) {
    if (choice >= reservedColorProfileIds) {
      _applyColorProfileMode(ColorProfileMode.custom, customId: choice);
      return;
    }
    _applyColorProfileMode(
      ColorProfileMode.values[choice.clamp(
        0,
        ColorProfileMode.values.length - 1,
      )],
    );
  }

  /// COLOR PROFILE section's mode dropdown — see [ColorProfileMode]'s doc.
  /// Resets Strength (Amount) to 100% and Contrast to that mode's default
  /// (mirrors [_applyWbMode]'s "picking a mode resets its own fields"
  /// convention), rather than leaving whatever values were dialed in
  /// under the previous mode — 2026-09-01, explicit user request.
  ///
  /// [customId] is the user profile to point at, and is only meaningful
  /// for [ColorProfileMode.custom]; every other mode clears it back to 0
  /// so a stale reference cannot outlive the switch away from it.
  void _applyColorProfileMode(ColorProfileMode mode, {int customId = 0}) {
    _rebuild(() {
      _paramValues = {
        ..._paramValues,
        colorProfileModeKey: storedValueForColorProfileMode(mode),
        customProfileIdKey: customId.toDouble(),
        _globalEditAmountKey: 100.0,
        'ColorProfileAmount': mode.contrastBaseline,
      };
    });
    _pushHistory();
    _scheduleRender(live: false);
    _scheduleCatalogSave();
  }
}
