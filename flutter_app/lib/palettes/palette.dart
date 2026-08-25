/// One named color inside an imported Adobe swatch file — [rgb] packed as
/// `0xRRGGBB`, matching how the rest of the app stores colors as ints
/// rather than a `Color`/`Uint8List` triple.
class PaletteSwatch {
  const PaletteSwatch({required this.name, required this.rgb});

  final String name;
  final int rgb;
}

/// One imported Adobe Color palette (.ase/.aco) — the whole file's swatches
/// kept together under the name the user imported it as, so they show up
/// as one group in the Color Grading panel rather than a single flat list
/// of every color ever imported.
class ColorPalette {
  const ColorPalette({
    required this.id,
    required this.name,
    required this.swatches,
  });

  final String id;
  final String name;
  final List<PaletteSwatch> swatches;
}
