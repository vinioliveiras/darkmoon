// The FILM section's imports (2026-09-13): the user's own `.cube` files
// and Hald CLUT images, picked from disk, kept by FilmLutLibrary under
// the documents folder and listed after the bundled stocks.
//
// A `part` of editor_screen.dart: same library, same private scope, no
// public API of its own.

part of '../editor_screen.dart';

extension _EditorFilm on _EditorScreenState {
  /// Where imports live: `<documents>/darkmoon/luts`. Null when the
  /// documents folder cannot be resolved (a widget test).
  Future<Directory?> _filmUserDir() async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(p.join(documents.path, 'darkmoon', 'luts'));
    } catch (_) {
      return null;
    }
  }

  /// Picks one or more LUT files, imports each, and selects the last one
  /// imported in the FILM dropdown. Files that are not tables are
  /// reported one by one; the rest still import.
  Future<void> _importFilmLuts() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.filmImportDialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['cube', 'png', 'jpg', 'jpeg', 'tif', 'tiff'],
      allowMultiple: true,
    );
    if (result == null || !mounted) {
      return;
    }
    var library = _filmLuts;
    if (library == null || library.userDir == null) {
      // Not loaded yet, or loaded before the documents folder resolved:
      // an empty library with a home is enough to import into.
      library = FilmLutLibrary.empty(userDir: await _filmUserDir());
      await library.loadUser();
      if (!mounted) {
        return;
      }
    }
    FilmLutEntry? last;
    var imported = 0;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) {
        continue;
      }
      try {
        last = await library.importFile(path);
        imported++;
      } catch (e) {
        if (!mounted) {
          return;
        }
        final message = e is FormatException ? e.message : e.toString();
        _notify(
          detail: l10n.filmImportFailedMessage(p.basename(path), message),
          status: l10n.filmImportFailedMessage(p.basename(path), message),
        );
      }
    }
    if (!mounted) {
      return;
    }
    _rebuild(() => _filmLuts = library);
    if (last != null) {
      _notify(
        detail: l10n.filmImportedMessage(imported),
        status: l10n.filmImportedMessage(imported),
      );
      if (_selectedIndex != null) {
        _onParamChanged(_filmKey, last.id.toDouble());
        _onParamChangeEnd(_filmKey, last.id.toDouble());
      }
    }
  }
}
