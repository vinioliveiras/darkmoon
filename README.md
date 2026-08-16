# Darkmoon

RAW photo editor for Windows, inspired by Lightroom and Photomator.

## Stack

- Python + PySide6 (Qt) for the interface
- rawpy (LibRaw) to decode RAW files
- NumPy + SciPy for image adjustments

## Current features

- Import a folder of RAW files (.CR2, .CR3, .NEF, .ARW, .DNG, .RAF, .ORF, .RW2), shown in a
  Lightroom-style filmstrip sorted by date
- White Balance (temperature in Kelvin, tint), Tone (exposure, brightness, contrast, highlights,
  shadows, whites, blacks) and Presence (texture, clarity, dehaze, vibrance, saturation)
- Fast, responsive editing preview (rendered on a downscaled copy of the image, in a background
  thread, with an even smaller live preview while dragging sliders)
- Zoom (Ctrl + scroll) and pan, plus a side-by-side Before/After view
- RGB histogram
- Export to PNG, TIFF or JPEG at full resolution
- Automatic catalog: edits and a thumbnail cache are stored under `Documents/darkmoon` and restored
  the next time you open a photo
- English/Portuguese interface, following the system language by default (changeable in Settings)

## Running it

```
python -m venv venv
venv\Scripts\activate
pip install rawpy numpy pillow pyside6 scipy
python main.py
```
