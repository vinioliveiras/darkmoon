/// Output formats offered by the export dialog, mirroring the Python app's
/// `ExportOptionsDialog.FORMATS`. JPEG listed first since it's the default.
enum ExportFormat {
  jpeg('JPEG', 'jpg'),
  png('PNG', 'png'),
  tiff('TIFF', 'tiff');

  const ExportFormat(this.label, this.extension);

  final String label;
  final String extension;

  bool get supportsQuality => this == ExportFormat.jpeg;
}
