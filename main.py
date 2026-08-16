import hashlib
import io
import json
import math
import os
import sqlite3
import sys
from datetime import datetime

import numpy as np
import rawpy
from PIL import Image, ImageOps
from PySide6.QtCore import (
    QLocale,
    QObject,
    QPoint,
    QPointF,
    QRectF,
    QRunnable,
    QSize,
    QStandardPaths,
    Qt,
    QThreadPool,
    QTimer,
    Signal,
)
from PySide6.QtGui import (
    QAction,
    QColor,
    QDoubleValidator,
    QIcon,
    QImage,
    QKeySequence,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
    QShortcut,
)
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QScrollArea,
    QSlider,
    QSpinBox,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)
from scipy.ndimage import gaussian_filter, minimum_filter, uniform_filter

APP_NAME = "Darkmoon"
RAW_EXTENSIONS = "RAW Files (*.cr2 *.cr3 *.nef *.arw *.dng *.raf *.orf *.rw2)"
RAW_EXTENSIONS_SET = {".cr2", ".cr3", ".nef", ".arw", ".dng", ".raf", ".orf", ".rw2"}
PREVIEW_MAX_DIM = 1600
LIVE_PREVIEW_MAX_DIM = 800
THUMB_MAX_DIM = 130
THUMB_ICON_SIZE = QSize(110, 74)
THUMB_CORNER_RADIUS = 8.0
DEBOUNCE_MS = 25
THUMBNAIL_THREADS = min(4, os.cpu_count() or 4)
CATALOG_SAVE_DEBOUNCE_MS = 800
APP_ICON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "icon.png")
TEMPERATURE_NEUTRAL_KELVIN = 5500.0


# ---------------------------------------------------------------------------
# Translations
# ---------------------------------------------------------------------------

TRANSLATIONS = {
    "en": {
        "placeholder_open_folder": "Open a folder with RAW files to get started",
        "menu_file": "&File",
        "action_open_file": "Open File",
        "action_open_folder": "Open Folder",
        "action_export": "Export",
        "action_settings": "Settings",
        "dialog_open_file_title": "Open RAW File",
        "dialog_open_folder_title": "Open Folder",
        "button_export": "Export...",
        "button_reset_tooltip": "Reset adjustments",
        "button_zoom_fit": "Fit to window",
        "zoom_label_fit": "Fit",
        "button_before_after": "Before/After",
        "caption_before": "BEFORE",
        "caption_after": "AFTER",
        "loading_thumbnails": "Loading thumbnails ({done}/{total})...",
        "loading_image": "Loading {name}...",
        "loading_exporting": "Exporting {name}...",
        "button_cancel": "Cancel",
        "button_ok": "OK",
        "button_close": "Close",
        "group_white_balance": "White Balance",
        "group_tone": "Tone",
        "group_presence": "Presence",
        "slider_temperature": "Temperature",
        "slider_tint": "Tint",
        "slider_exposure": "Exposure",
        "slider_brightness": "Brightness",
        "slider_contrast": "Contrast",
        "slider_highlights": "Highlights",
        "slider_shadows": "Shadows",
        "slider_whites": "Whites",
        "slider_blacks": "Blacks",
        "slider_texture": "Texture",
        "slider_clarity": "Clarity",
        "slider_dehaze": "Dehaze",
        "slider_vibrance": "Vibrance",
        "slider_saturation": "Saturation",
        "slider_click_to_edit": "Click to type a value",
        "export_dialog_title": "Export Options",
        "export_format_label": "Format:",
        "export_quality_label": "Quality:",
        "export_format_png": "PNG (lossless, recommended)",
        "export_format_tiff": "TIFF (lossless)",
        "export_format_jpeg": "JPEG",
        "export_save_dialog_title": "Export Image",
        "export_success_title": "Export",
        "export_success_message": "Image exported to:\n{path}",
        "export_failure_message": "Failed to export image:\n{error}",
        "settings_dialog_title": "Settings",
        "settings_language_label": "Language:",
        "settings_language_auto": "Automatic (system)",
        "settings_language_en": "English",
        "settings_language_pt": "Português",
        "settings_language_restart_note": "Language changes take effect after restarting the app.",
        "settings_fast_preview_label": "Fast preview while dragging sliders",
        "settings_thumbnail_threads_label": "Thumbnail loading threads:",
        "settings_clear_cache_button": "Clear thumbnail cache",
        "settings_clear_cache_done": "Thumbnail cache cleared.",
    },
    "pt": {
        "placeholder_open_folder": "Abra uma pasta com arquivos RAW para começar",
        "menu_file": "&Arquivo",
        "action_open_file": "Abrir arquivo...",
        "action_open_folder": "Abrir pasta...",
        "action_export": "Exportar...",
        "action_settings": "Configurações...",
        "dialog_open_file_title": "Abrir arquivo RAW",
        "dialog_open_folder_title": "Abrir pasta",
        "button_export": "Exportar...",
        "button_reset_tooltip": "Redefinir ajustes",
        "button_zoom_fit": "Ajustar à janela",
        "zoom_label_fit": "Ajustar",
        "button_before_after": "Antes/Depois (\\)",
        "caption_before": "ANTES",
        "caption_after": "DEPOIS",
        "loading_thumbnails": "Carregando miniaturas ({done}/{total})...",
        "loading_image": "Carregando {name}...",
        "loading_exporting": "Exportando {name}...",
        "button_cancel": "Cancelar",
        "button_ok": "OK",
        "button_close": "Fechar",
        "group_white_balance": "Balanço de Branco",
        "group_tone": "Tom",
        "group_presence": "Presença",
        "slider_temperature": "Temperatura",
        "slider_tint": "Matiz",
        "slider_exposure": "Exposição",
        "slider_brightness": "Brilho",
        "slider_contrast": "Contraste",
        "slider_highlights": "Realces",
        "slider_shadows": "Sombras",
        "slider_whites": "Brancos",
        "slider_blacks": "Pretos",
        "slider_texture": "Textura",
        "slider_clarity": "Claridade",
        "slider_dehaze": "Remoção de Neblina",
        "slider_vibrance": "Vibração",
        "slider_saturation": "Saturação",
        "slider_click_to_edit": "Clique para digitar um valor",
        "export_dialog_title": "Opções de exportação",
        "export_format_label": "Formato:",
        "export_quality_label": "Qualidade:",
        "export_format_png": "PNG (sem perdas, recomendado)",
        "export_format_tiff": "TIFF (sem perdas)",
        "export_format_jpeg": "JPEG",
        "export_save_dialog_title": "Exportar imagem",
        "export_success_title": "Exportar",
        "export_success_message": "Imagem exportada em:\n{path}",
        "export_failure_message": "Falha ao exportar a imagem:\n{error}",
        "settings_dialog_title": "Configurações",
        "settings_language_label": "Idioma:",
        "settings_language_auto": "Automático (sistema)",
        "settings_language_en": "English",
        "settings_language_pt": "Português",
        "settings_language_restart_note": "A mudança de idioma tem efeito após reiniciar o aplicativo.",
        "settings_fast_preview_label": "Preview rápido ao arrastar os sliders",
        "settings_thumbnail_threads_label": "Threads de carregamento de miniaturas:",
        "settings_clear_cache_button": "Limpar cache de miniaturas",
        "settings_clear_cache_done": "Cache de miniaturas limpo.",
    },
}

_CURRENT_LANGUAGE = "en"


def set_language(lang: str) -> None:
    global _CURRENT_LANGUAGE
    _CURRENT_LANGUAGE = lang if lang in TRANSLATIONS else "en"


def tr(key: str, **kwargs) -> str:
    text = TRANSLATIONS.get(_CURRENT_LANGUAGE, {}).get(key) or TRANSLATIONS["en"].get(key, key)
    return text.format(**kwargs) if kwargs else text


def detect_system_language() -> str:
    locale_name = QLocale.system().name()  # e.g. "pt_BR", "en_US"
    return "pt" if locale_name.lower().startswith("pt") else "en"


def resolve_language(setting: str) -> str:
    if setting == "auto":
        return detect_system_language()
    return setting if setting in TRANSLATIONS else "en"


# ---------------------------------------------------------------------------
# Settings persistence
# ---------------------------------------------------------------------------

DEFAULT_SETTINGS = {
    "language": "auto",
    "fast_preview": True,
    "thumbnail_threads": THUMBNAIL_THREADS,
}


def load_settings() -> dict:
    path = os.path.join(catalog_dir_bootstrap(), "settings.json")
    settings = dict(DEFAULT_SETTINGS)
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                settings.update(json.load(f))
        except Exception:
            pass
    return settings


def save_settings(settings: dict) -> None:
    path = os.path.join(catalog_dir_bootstrap(), "settings.json")
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(settings, f)
    os.replace(tmp_path, path)


def catalog_dir_bootstrap() -> str:
    # Used before QApplication exists (QStandardPaths still works without one on Windows).
    documents = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.DocumentsLocation)
    path = os.path.join(documents, "darkmoon")
    os.makedirs(path, exist_ok=True)
    return path


# ---------------------------------------------------------------------------
# RAW decoding / preview generation
# ---------------------------------------------------------------------------


def load_raw_as_rgb(path: str) -> np.ndarray:
    with rawpy.imread(path) as raw:
        # half_size skips full demosaicing (much faster, especially on X-Trans sensors).
        # Still comfortably above PREVIEW_MAX_DIM for editing, since we're not exporting full-res yet.
        rgb = raw.postprocess(use_camera_wb=True, output_bps=8, half_size=True)
    return rgb


def make_preview(image: np.ndarray, max_dim: int = PREVIEW_MAX_DIM) -> np.ndarray:
    height, width = image.shape[:2]
    longest = max(height, width)
    if longest <= max_dim:
        return image
    scale = max_dim / longest
    new_size = (int(width * scale), int(height * scale))
    resized = Image.fromarray(image).resize(new_size, Image.Resampling.LANCZOS)
    return np.array(resized)


def catalog_dir() -> str:
    return catalog_dir_bootstrap()


def thumbnail_cache_dir() -> str:
    path = os.path.join(catalog_dir(), "thumbnails")
    os.makedirs(path, exist_ok=True)
    return path


def _thumbnail_archive_path(source_path: str, stat: os.stat_result) -> str:
    # One SQLite file per capture month (by file mtime) instead of one file per photo,
    # so a folder with thousands of RAWs doesn't turn into thousands of loose cache files.
    month_key = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m")
    return os.path.join(thumbnail_cache_dir(), f"{month_key}.sqlite")


def _thumbnail_cache_key(source_path: str, stat: os.stat_result) -> str:
    key = f"{source_path}|{stat.st_mtime_ns}|{stat.st_size}"
    return hashlib.sha1(key.encode("utf-8")).hexdigest()


def _open_thumbnail_db(archive_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(archive_path, timeout=5.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("CREATE TABLE IF NOT EXISTS thumbnails (key TEXT PRIMARY KEY, data BLOB NOT NULL)")
    return conn


def load_cached_thumbnail(path: str) -> np.ndarray | None:
    try:
        stat = os.stat(path)
    except OSError:
        return None
    archive_path = _thumbnail_archive_path(path, stat)
    if not os.path.isfile(archive_path):
        return None
    key = _thumbnail_cache_key(path, stat)
    try:
        conn = _open_thumbnail_db(archive_path)
        try:
            row = conn.execute("SELECT data FROM thumbnails WHERE key = ?", (key,)).fetchone()
        finally:
            conn.close()
        if row is None:
            return None
        return np.array(Image.open(io.BytesIO(row[0])).convert("RGB"))
    except Exception:
        return None


def save_thumbnail_cache(path: str, image: np.ndarray) -> None:
    try:
        stat = os.stat(path)
    except OSError:
        return
    archive_path = _thumbnail_archive_path(path, stat)
    key = _thumbnail_cache_key(path, stat)
    buffer = io.BytesIO()
    try:
        Image.fromarray(image).save(buffer, "JPEG", quality=85)
    except Exception:
        return
    data = buffer.getvalue()
    try:
        conn = _open_thumbnail_db(archive_path)
        try:
            conn.execute(
                "INSERT INTO thumbnails (key, data) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET data = excluded.data",
                (key, data),
            )
            conn.commit()
        finally:
            conn.close()
    except Exception:
        pass


def clear_thumbnail_cache() -> None:
    cache_dir = thumbnail_cache_dir()
    for name in os.listdir(cache_dir):
        try:
            os.remove(os.path.join(cache_dir, name))
        except OSError:
            pass


def load_catalog() -> dict:
    path = os.path.join(catalog_dir(), "catalog.json")
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_catalog(edits: dict) -> None:
    path = os.path.join(catalog_dir(), "catalog.json")
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(edits, f)
    os.replace(tmp_path, path)


def _apply_flip(image: np.ndarray, flip: int) -> np.ndarray:
    if flip == 3:
        return np.rot90(image, 2)
    if flip == 5:
        return np.rot90(image, 1)
    if flip == 6:
        return np.rot90(image, -1)
    return image


def list_raw_files(folder: str) -> list[str]:
    entries = []
    with os.scandir(folder) as it:
        for entry in it:
            if entry.is_file() and os.path.splitext(entry.name)[1].lower() in RAW_EXTENSIONS_SET:
                entries.append((entry.path, entry.stat().st_mtime))
    entries.sort(key=lambda e: e[1], reverse=True)
    return [path for path, _ in entries]


def extract_raw_thumbnail(path: str, max_dim: int = THUMB_MAX_DIM) -> np.ndarray:
    with rawpy.imread(path) as raw:
        thumb = None
        try:
            thumb = raw.extract_thumb()
        except (rawpy.LibRawNoThumbnailError, rawpy.LibRawUnsupportedThumbnailError):
            thumb = None
        if thumb is not None and thumb.format == rawpy.ThumbFormat.JPEG:
            pil_image = Image.open(io.BytesIO(thumb.data))
            # Decoding directly at a reduced DCT scale is much faster than a full decode + resize.
            pil_image.draft("RGB", (max_dim, max_dim))
            pil_image = ImageOps.exif_transpose(pil_image)
            if pil_image.mode != "RGB":
                pil_image = pil_image.convert("RGB")
            image = np.array(pil_image)
        elif thumb is not None and thumb.format == rawpy.ThumbFormat.BITMAP:
            image = _apply_flip(thumb.data, raw.sizes.flip)
        else:
            image = raw.postprocess(use_camera_wb=True, output_bps=8, half_size=True)
    return make_preview(image, max_dim)


# ---------------------------------------------------------------------------
# Image processing pipeline
# ---------------------------------------------------------------------------


def apply_white_balance(image: np.ndarray, temperature_kelvin: float, tint: float) -> np.ndarray:
    # temperature_kelvin is an absolute color temperature (like Lightroom's Temp slider),
    # converted to a gain delta around a neutral daylight reference.
    delta = (temperature_kelvin - TEMPERATURE_NEUTRAL_KELVIN) / TEMPERATURE_NEUTRAL_KELVIN * 100.0
    if delta == 0 and tint == 0:
        return image
    r_gain = 1.0 + (delta / 100.0) * 0.3
    b_gain = 1.0 - (delta / 100.0) * 0.3
    g_gain = 1.0 - (tint / 100.0) * 0.2
    image[..., 0] *= r_gain
    image[..., 1] *= g_gain
    image[..., 2] *= b_gain
    return image


def apply_exposure(image: np.ndarray, exposure: float) -> np.ndarray:
    if exposure == 0:
        return image
    stops = exposure / 100.0 * 3.0
    return image * (2.0**stops)


def apply_brightness_contrast(image: np.ndarray, brightness: float, contrast: float) -> np.ndarray:
    if brightness == 0 and contrast == 0:
        return image
    contrast_factor = 1.0 + contrast / 100.0
    return (image - 127.5) * contrast_factor + 127.5 + brightness


def apply_highlights_shadows(image: np.ndarray, highlights: float, shadows: float) -> np.ndarray:
    if highlights == 0 and shadows == 0:
        return image
    luminance = image.mean(axis=2, keepdims=True) / 255.0
    if shadows != 0:
        shadow_weight = np.clip(1.0 - luminance * 2.0, 0.0, 1.0)
        image = image + shadow_weight * (shadows / 100.0) * 80.0
    if highlights != 0:
        highlight_weight = np.clip((luminance - 0.5) * 2.0, 0.0, 1.0)
        image = image + highlight_weight * (highlights / 100.0) * 80.0
    return image


def apply_whites_blacks(image: np.ndarray, whites: float, blacks: float) -> np.ndarray:
    if whites == 0 and blacks == 0:
        return image
    luminance = image.mean(axis=2, keepdims=True) / 255.0
    if whites != 0:
        white_weight = np.clip((luminance - 0.75) * 4.0, 0.0, 1.0)
        image = image + white_weight * (whites / 100.0) * 100.0
    if blacks != 0:
        black_weight = np.clip(1.0 - luminance * 4.0, 0.0, 1.0)
        image = image + black_weight * (blacks / 100.0) * 100.0
    return image


def apply_vibrance(image: np.ndarray, amount: float) -> np.ndarray:
    if amount == 0:
        return image
    luminance = image.mean(axis=2, keepdims=True)
    channel_range = image.max(axis=2, keepdims=True) - image.min(axis=2, keepdims=True)
    current_saturation = channel_range / 255.0
    factor = 1.0 + (amount / 100.0) * (1.0 - current_saturation)
    return luminance + (image - luminance) * factor


def apply_saturation(image: np.ndarray, amount: float) -> np.ndarray:
    if amount == 0:
        return image
    luminance = image.mean(axis=2, keepdims=True)
    factor = 1.0 + amount / 100.0
    return luminance + (image - luminance) * factor


def apply_local_contrast(
    image: np.ndarray, amount: float, radius: float, protect_midtones: bool = False
) -> np.ndarray:
    if amount == 0:
        return image
    blurred = gaussian_filter(image, sigma=(radius, radius, 0))
    high_freq = image - blurred
    if protect_midtones:
        luminance = image.mean(axis=2, keepdims=True) / 255.0
        weight = 1.0 - np.abs(luminance - 0.5) * 2.0
        weight = np.clip(weight, 0.15, 1.0)
        high_freq = high_freq * weight
    return image + high_freq * (amount / 100.0)


def apply_dehaze(image: np.ndarray, amount: float) -> np.ndarray:
    if amount == 0:
        return image
    img = image / 255.0
    strength = amount / 100.0

    dark_channel = minimum_filter(img.min(axis=2), size=15)
    flat_img = img.reshape(-1, 3)
    flat_dark = dark_channel.reshape(-1)
    num_pixels = max(int(flat_dark.size * 0.001), 1)
    brightest_idx = np.argpartition(flat_dark, -num_pixels)[-num_pixels:]
    atmospheric_light = np.clip(flat_img[brightest_idx].max(axis=0), 0.5, 1.0)

    normalized_dark = minimum_filter((img / atmospheric_light).min(axis=2), size=15)
    transmission = uniform_filter(1.0 - 0.9 * normalized_dark, size=41)
    transmission = np.clip(transmission, 0.2, 1.0)

    if strength >= 0:
        t = 1.0 - strength * (1.0 - transmission)
        recovered = (img - atmospheric_light) / t[..., None] + atmospheric_light
    else:
        haze_amount = -strength
        recovered = img * (1.0 - haze_amount) + atmospheric_light * haze_amount

    return recovered * 255.0


def render(image: np.ndarray, params: dict) -> np.ndarray:
    img = image.astype(np.float32)
    img = apply_white_balance(img, params["temperature"], params["tint"])
    img = apply_exposure(img, params["exposure"])
    img = apply_brightness_contrast(img, params["brightness"], params["contrast"])
    img = apply_highlights_shadows(img, params["highlights"], params["shadows"])
    img = apply_whites_blacks(img, params["whites"], params["blacks"])
    img = apply_local_contrast(img, params["texture"], radius=3)
    img = apply_local_contrast(img, params["clarity"], radius=25, protect_midtones=True)
    img = apply_dehaze(img, params["dehaze"])
    img = apply_vibrance(img, params["vibrance"])
    img = apply_saturation(img, params["saturation"])
    return np.clip(img, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# Background tasks
# ---------------------------------------------------------------------------


class RenderSignals(QObject):
    finished = Signal(int, object)


class RenderTask(QRunnable):
    def __init__(self, generation: int, image: np.ndarray, params: dict):
        super().__init__()
        self.generation = generation
        self.image = image
        self.params = params
        self.signals = RenderSignals()

    def run(self):
        result = render(self.image, self.params)
        self.signals.finished.emit(self.generation, result)


class ThumbnailSignals(QObject):
    finished = Signal(str, int, object)


class ThumbnailTask(QRunnable):
    def __init__(self, path: str, generation: int):
        super().__init__()
        self.path = path
        self.generation = generation
        self.signals = ThumbnailSignals()

    def run(self):
        try:
            image = load_cached_thumbnail(self.path)
            if image is None:
                image = extract_raw_thumbnail(self.path)
                save_thumbnail_cache(self.path, image)
        except Exception:
            image = None
        self.signals.finished.emit(self.path, self.generation, image)


class ImageLoadSignals(QObject):
    finished = Signal(str, int, object, object, object)


class ImageLoadTask(QRunnable):
    def __init__(self, path: str, generation: int):
        super().__init__()
        self.path = path
        self.generation = generation
        self.signals = ImageLoadSignals()

    def run(self):
        try:
            full_image = load_raw_as_rgb(self.path)
            preview_source = make_preview(full_image)
            live_preview_source = make_preview(full_image, LIVE_PREVIEW_MAX_DIM)
        except Exception:
            full_image = preview_source = live_preview_source = None
        self.signals.finished.emit(self.path, self.generation, full_image, preview_source, live_preview_source)


class ExportSignals(QObject):
    finished = Signal(bool, str)


class ExportTask(QRunnable):
    def __init__(self, source_path: str, dest_path: str, params: dict, image_format: str, quality: int):
        super().__init__()
        self.source_path = source_path
        self.dest_path = dest_path
        self.params = params
        self.image_format = image_format
        self.quality = quality
        self.signals = ExportSignals()

    def run(self):
        try:
            with rawpy.imread(self.source_path) as raw:
                # Full quality (no half_size) for the exported file, unlike the fast editing preview.
                full = raw.postprocess(use_camera_wb=True, output_bps=8)
            result = render(full, self.params)
            image = Image.fromarray(result)
            if self.image_format == "JPEG":
                image.save(self.dest_path, "JPEG", quality=self.quality)
            else:
                image.save(self.dest_path, self.image_format)
            self.signals.finished.emit(True, self.dest_path)
        except Exception as exc:
            self.signals.finished.emit(False, str(exc))


# ---------------------------------------------------------------------------
# Pixmap helpers
# ---------------------------------------------------------------------------


def rgb_array_to_pixmap(image: np.ndarray) -> QPixmap:
    height, width, _ = image.shape
    contiguous = np.ascontiguousarray(image)
    qimage = QImage(contiguous.data, width, height, width * 3, QImage.Format.Format_RGB888)
    return QPixmap.fromImage(qimage.copy())


def rounded_pixmap(pixmap: QPixmap, radius: float) -> QPixmap:
    result = QPixmap(pixmap.size())
    result.fill(Qt.GlobalColor.transparent)
    painter = QPainter(result)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    path = QPainterPath()
    path.addRoundedRect(QRectF(0, 0, pixmap.width(), pixmap.height()), radius, radius)
    painter.setClipPath(path)
    painter.drawPixmap(0, 0, pixmap)
    painter.end()
    return result


# ---------------------------------------------------------------------------
# Hand-drawn monochrome icons (no external assets required)
# ---------------------------------------------------------------------------

ICON_COLOR = "#3c3c40"


def _icon_pen(painter: QPainter, width: float = 1.7):
    pen = QPen(QColor(ICON_COLOR))
    pen.setWidthF(width)
    pen.setCapStyle(Qt.PenCapStyle.RoundCap)
    pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
    painter.setPen(pen)


def _draw_file_icon(painter: QPainter, size: float):
    m = size * 0.24
    fold = size * 0.26
    top = size * 0.12
    bottom = size * 0.88
    left, right = m, size - m
    path = QPainterPath()
    path.moveTo(left, top)
    path.lineTo(right - fold, top)
    path.lineTo(right, top + fold)
    path.lineTo(right, bottom)
    path.lineTo(left, bottom)
    path.closeSubpath()
    painter.drawPath(path)
    painter.drawLine(QPointF(right - fold, top), QPointF(right - fold, top + fold))
    painter.drawLine(QPointF(right - fold, top + fold), QPointF(right, top + fold))


def _draw_folder_icon(painter: QPainter, size: float):
    m = size * 0.14
    top = size * 0.34
    tab_w = size * 0.3
    path = QPainterPath()
    path.moveTo(m, size - m)
    path.lineTo(m, top)
    path.lineTo(m + tab_w, top)
    path.lineTo(m + tab_w + size * 0.1, top - size * 0.12)
    path.lineTo(size - m, top - size * 0.12)
    path.lineTo(size - m, size - m)
    path.closeSubpath()
    painter.drawPath(path)


def _draw_export_icon(painter: QPainter, size: float):
    cx = size / 2
    top = size * 0.14
    tip = size * 0.58
    painter.drawLine(QPointF(cx, top), QPointF(cx, tip))
    painter.drawLine(QPointF(cx - size * 0.18, tip - size * 0.18), QPointF(cx, tip))
    painter.drawLine(QPointF(cx + size * 0.18, tip - size * 0.18), QPointF(cx, tip))
    tray_y = size * 0.82
    painter.drawLine(QPointF(size * 0.2, tray_y), QPointF(size * 0.8, tray_y))
    painter.drawLine(QPointF(size * 0.2, tray_y), QPointF(size * 0.2, tray_y - size * 0.14))
    painter.drawLine(QPointF(size * 0.8, tray_y), QPointF(size * 0.8, tray_y - size * 0.14))


def _draw_reset_icon(painter: QPainter, size: float):
    cx, cy, r = size / 2, size / 2, size * 0.32
    start_deg, span_deg = 40, 280
    rect = QRectF(cx - r, cy - r, 2 * r, 2 * r)
    painter.drawArc(rect, int(start_deg * 16), int(span_deg * 16))
    end_rad = math.radians(start_deg)
    tip_x = cx + r * math.cos(end_rad)
    tip_y = cy - r * math.sin(end_rad)
    arrow_len = size * 0.16
    for ang_off in (150, -150):
        ang = end_rad + math.radians(ang_off)
        ax = tip_x + arrow_len * math.cos(ang)
        ay = tip_y - arrow_len * math.sin(ang)
        painter.drawLine(QPointF(tip_x, tip_y), QPointF(ax, ay))


def _draw_compare_icon(painter: QPainter, size: float):
    rect = QRectF(size * 0.14, size * 0.14, size * 0.72, size * 0.72)
    painter.drawEllipse(rect)
    painter.setBrush(QColor(ICON_COLOR))
    painter.drawPie(rect, 90 * 16, 180 * 16)
    painter.setBrush(Qt.BrushStyle.NoBrush)
    painter.drawLine(QPointF(rect.center().x(), rect.top()), QPointF(rect.center().x(), rect.bottom()))


def make_icon(draw_fn, size: int = 18) -> QIcon:
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    _icon_pen(painter)
    draw_fn(painter, size)
    painter.end()
    return QIcon(pixmap)


# ---------------------------------------------------------------------------
# Small reusable widgets
# ---------------------------------------------------------------------------


class LoadingOverlay(QWidget):
    cancelled = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)
        self.setStyleSheet("background-color: rgba(0, 0, 0, 150);")

        self.message_label = QLabel("")
        self.message_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.message_label.setStyleSheet("color: #eee; font-size: 13px;")

        self.progress_bar = QProgressBar()
        self.progress_bar.setFixedWidth(320)
        self.progress_bar.setFixedHeight(2)
        self.progress_bar.setTextVisible(False)

        self.cancel_button = QPushButton(tr("button_cancel"))
        self.cancel_button.clicked.connect(self.cancelled.emit)

        panel_layout = QVBoxLayout()
        panel_layout.setSpacing(14)
        panel_layout.addWidget(self.message_label)
        panel_layout.addWidget(self.progress_bar)
        panel_layout.addWidget(self.cancel_button, alignment=Qt.AlignmentFlag.AlignCenter)

        panel = QFrame()
        panel.setLayout(panel_layout)
        panel.setFixedWidth(360)
        panel.setStyleSheet(
            "QFrame { background-color: #232326; border: 1px solid #34343a; border-radius: 12px; padding: 20px; }"
        )

        center_row = QHBoxLayout()
        center_row.addStretch()
        center_row.addWidget(panel)
        center_row.addStretch()

        outer_layout = QVBoxLayout(self)
        outer_layout.addStretch()
        outer_layout.addLayout(center_row)
        outer_layout.addStretch()

        self.hide()

    def start(self, message: str, maximum: int = 0, cancellable: bool = True):
        self.message_label.setText(message)
        self.progress_bar.setMaximum(maximum)
        self.progress_bar.setValue(0)
        self.cancel_button.setVisible(cancellable)
        self.show()
        self.raise_()

    def set_progress(self, value: int, message: str | None = None):
        self.progress_bar.setValue(value)
        if message is not None:
            self.message_label.setText(message)

    def finish(self):
        self.hide()


class HistogramWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(64)
        self._hist_r: np.ndarray | None = None
        self._hist_g: np.ndarray | None = None
        self._hist_b: np.ndarray | None = None
        self.setStyleSheet("background-color: #141416; border-radius: 6px;")

    def set_image(self, image: np.ndarray | None):
        if image is None:
            self._hist_r = self._hist_g = self._hist_b = None
        else:
            bins = 64
            self._hist_r = np.histogram(image[..., 0], bins=bins, range=(0, 255))[0]
            self._hist_g = np.histogram(image[..., 1], bins=bins, range=(0, 255))[0]
            self._hist_b = np.histogram(image[..., 2], bins=bins, range=(0, 255))[0]
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        rect = self.rect()
        painter.fillRect(rect, QColor("#141416"))
        if self._hist_r is None:
            painter.end()
            return
        max_val = max(int(self._hist_r.max()), int(self._hist_g.max()), int(self._hist_b.max()), 1)
        painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_Plus)
        painter.setPen(Qt.PenStyle.NoPen)
        for hist, color in (
            (self._hist_r, QColor(255, 90, 90, 140)),
            (self._hist_g, QColor(90, 255, 130, 140)),
            (self._hist_b, QColor(100, 150, 255, 140)),
        ):
            n = len(hist)
            step = rect.width() / n
            path = QPainterPath()
            path.moveTo(0, rect.height())
            for i, v in enumerate(hist):
                x = i * step
                h = (v / max_val) * (rect.height() - 4)
                path.lineTo(x, rect.height() - h)
            path.lineTo(rect.width(), rect.height())
            path.closeSubpath()
            painter.setBrush(color)
            painter.drawPath(path)
        painter.end()


class ClickableLabel(QLabel):
    clicked = Signal()

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()
        super().mousePressEvent(event)


class ImageView(QLabel):
    wheelZoom = Signal(int, QPoint)
    dragPanned = Signal(QPoint)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._drag_origin: QPoint | None = None

    def wheelEvent(self, event):
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            delta = event.angleDelta().y()
            if delta != 0:
                self.wheelZoom.emit(delta, event.globalPosition().toPoint())
                event.accept()
                return
        super().wheelEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_origin = event.globalPosition().toPoint()
            self.setCursor(Qt.CursorShape.ClosedHandCursor)
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self._drag_origin is not None:
            current = event.globalPosition().toPoint()
            self.dragPanned.emit(current - self._drag_origin)
            self._drag_origin = current
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_origin = None
            self.setCursor(Qt.CursorShape.ArrowCursor)
        super().mouseReleaseEvent(event)


class ScrollSafeSlider(QSlider):
    def wheelEvent(self, event):
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            super().wheelEvent(event)
        else:
            event.ignore()


class SliderControl(QWidget):
    """A labeled slider whose current value can also be clicked and typed directly."""

    valueChanged = Signal(str, float)
    sliderPressed = Signal(str)
    sliderReleased = Signal(str)

    def __init__(
        self,
        key: str,
        name: str,
        minimum: float,
        maximum: float,
        default: float = 0.0,
        decimals: int = 2,
        parent=None,
    ):
        super().__init__(parent)
        self.key = key
        self.minimum = minimum
        self.maximum = maximum
        self.default = default
        self.decimals = decimals
        self.scale = 10**decimals
        self._committing = False

        self.name_label = QLabel(name)
        self.name_label.setStyleSheet("color: #c8c8cc; font-size: 11.5px;")

        self.value_label = ClickableLabel(self._format(default))
        self.value_label.setStyleSheet("color: #9a9aa2; font-size: 11.5px;")
        self.value_label.setCursor(Qt.CursorShape.IBeamCursor)
        self.value_label.setToolTip(tr("slider_click_to_edit"))
        self.value_label.clicked.connect(self._start_editing)

        self.value_edit = QLineEdit()
        validator = QDoubleValidator(minimum, maximum, decimals, self.value_edit)
        validator.setNotation(QDoubleValidator.Notation.StandardNotation)
        self.value_edit.setValidator(validator)
        self.value_edit.setFixedWidth(64)
        self.value_edit.setAlignment(Qt.AlignmentFlag.AlignRight)
        self.value_edit.setStyleSheet("padding: 1px 4px;")
        self.value_edit.editingFinished.connect(self._commit_edit)

        self.value_stack = QStackedWidget()
        self.value_stack.addWidget(self.value_label)
        self.value_stack.addWidget(self.value_edit)
        self.value_stack.setFixedHeight(18)

        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        header.addWidget(self.name_label)
        header.addStretch()
        header.addWidget(self.value_stack)

        self.slider = ScrollSafeSlider(Qt.Orientation.Horizontal)
        self.slider.setMinimum(round(minimum * self.scale))
        self.slider.setMaximum(round(maximum * self.scale))
        self.slider.setValue(round(default * self.scale))
        self.slider.valueChanged.connect(self._on_slider_value_changed)
        self.slider.sliderPressed.connect(lambda: self.sliderPressed.emit(self.key))
        self.slider.sliderReleased.connect(lambda: self.sliderReleased.emit(self.key))

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)
        layout.addLayout(header)
        layout.addWidget(self.slider)

    def _format(self, value: float) -> str:
        return f"{value:.{self.decimals}f}"

    def value(self) -> float:
        return self.slider.value() / self.scale

    def set_value(self, value: float, emit: bool):
        value = max(self.minimum, min(self.maximum, value))
        raw = round(value * self.scale)
        if emit:
            self.slider.setValue(raw)
        else:
            self.slider.blockSignals(True)
            self.slider.setValue(raw)
            self.value_label.setText(self._format(raw / self.scale))
            self.slider.blockSignals(False)

    def reset(self):
        self.set_value(self.default, emit=False)

    def _on_slider_value_changed(self, raw: int):
        value = raw / self.scale
        self.value_label.setText(self._format(value))
        self.valueChanged.emit(self.key, value)

    def _start_editing(self):
        self.value_edit.setText(self._format(self.value()))
        self.value_stack.setCurrentWidget(self.value_edit)
        self.value_edit.selectAll()
        self.value_edit.setFocus()

    def _commit_edit(self):
        if self._committing:
            return
        self._committing = True
        try:
            self.value_stack.setCurrentWidget(self.value_label)
            text = self.value_edit.text().strip().replace(",", ".")
            try:
                value = float(text)
            except ValueError:
                value = self.value()
            self.set_value(value, emit=True)
        finally:
            self._committing = False


class ExportOptionsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle(tr("export_dialog_title"))
        self.FORMATS = [
            (tr("export_format_png"), "PNG", "png"),
            (tr("export_format_tiff"), "TIFF", "tiff"),
            (tr("export_format_jpeg"), "JPEG", "jpg"),
        ]

        self.format_combo = QComboBox()
        for label, _fmt, _ext in self.FORMATS:
            self.format_combo.addItem(label)
        self.format_combo.setCurrentIndex(0)
        self.format_combo.currentIndexChanged.connect(self._on_format_changed)

        self.quality_spin = QSpinBox()
        self.quality_spin.setRange(1, 100)
        self.quality_spin.setValue(95)
        self.quality_spin.setEnabled(False)

        form = QFormLayout()
        form.addRow(tr("export_format_label"), self.format_combo)
        form.addRow(tr("export_quality_label"), self.quality_spin)

        buttons = QDialogButtonBox()
        ok_button = buttons.addButton(tr("button_ok"), QDialogButtonBox.ButtonRole.AcceptRole)
        cancel_button = buttons.addButton(tr("button_cancel"), QDialogButtonBox.ButtonRole.RejectRole)
        ok_button.clicked.connect(self.accept)
        cancel_button.clicked.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.addLayout(form)
        layout.addWidget(buttons)

    def _on_format_changed(self, index: int):
        self.quality_spin.setEnabled(self.FORMATS[index][1] == "JPEG")

    def selected_format(self) -> str:
        return self.FORMATS[self.format_combo.currentIndex()][1]

    def selected_extension(self) -> str:
        return self.FORMATS[self.format_combo.currentIndex()][2]

    def selected_quality(self) -> int:
        return self.quality_spin.value()


class SettingsDialog(QDialog):
    def __init__(self, settings: dict, thumbnail_pool: QThreadPool, parent=None):
        super().__init__(parent)
        self.settings = settings
        self.thumbnail_pool = thumbnail_pool
        self.setWindowTitle(tr("settings_dialog_title"))

        self.language_combo = QComboBox()
        self.language_combo.addItem(tr("settings_language_auto"), "auto")
        self.language_combo.addItem(tr("settings_language_en"), "en")
        self.language_combo.addItem(tr("settings_language_pt"), "pt")
        current_index = self.language_combo.findData(settings.get("language", "auto"))
        self.language_combo.setCurrentIndex(max(0, current_index))
        self.language_combo.currentIndexChanged.connect(self._on_language_changed)

        self.restart_note = QLabel(tr("settings_language_restart_note"))
        self.restart_note.setStyleSheet("color: #8a8a90; font-size: 10.5px;")
        self.restart_note.setWordWrap(True)
        self.restart_note.setVisible(False)

        self.fast_preview_check = QCheckBox(tr("settings_fast_preview_label"))
        self.fast_preview_check.setChecked(settings.get("fast_preview", True))
        self.fast_preview_check.toggled.connect(self._on_fast_preview_toggled)

        self.thumbnail_threads_spin = QSpinBox()
        self.thumbnail_threads_spin.setRange(1, max(1, os.cpu_count() or 4))
        self.thumbnail_threads_spin.setValue(settings.get("thumbnail_threads", THUMBNAIL_THREADS))
        self.thumbnail_threads_spin.valueChanged.connect(self._on_thumbnail_threads_changed)

        clear_cache_button = QPushButton(tr("settings_clear_cache_button"))
        clear_cache_button.clicked.connect(self._on_clear_cache)

        form = QFormLayout()
        form.addRow(tr("settings_language_label"), self.language_combo)
        form.addRow("", self.restart_note)
        form.addRow(self.fast_preview_check)
        form.addRow(tr("settings_thumbnail_threads_label"), self.thumbnail_threads_spin)
        form.addRow(clear_cache_button)

        buttons = QDialogButtonBox()
        close_button = buttons.addButton(tr("button_close"), QDialogButtonBox.ButtonRole.RejectRole)
        close_button.clicked.connect(self.close)

        layout = QVBoxLayout(self)
        layout.addLayout(form)
        layout.addWidget(buttons)

    def _on_language_changed(self, _index: int):
        self.settings["language"] = self.language_combo.currentData()
        save_settings(self.settings)
        self.restart_note.setVisible(True)

    def _on_fast_preview_toggled(self, checked: bool):
        self.settings["fast_preview"] = checked
        save_settings(self.settings)

    def _on_thumbnail_threads_changed(self, value: int):
        self.settings["thumbnail_threads"] = value
        save_settings(self.settings)
        self.thumbnail_pool.setMaxThreadCount(value)

    def _on_clear_cache(self):
        clear_thumbnail_cache()
        QMessageBox.information(self, tr("settings_dialog_title"), tr("settings_clear_cache_done"))


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------


class MainWindow(QMainWindow):
    MIN_ZOOM = 0.1
    MAX_ZOOM = 4.0
    ZOOM_STEP = 1.15

    # (key, name_key, group_key, minimum, maximum, default, decimals)
    SLIDER_SPECS = [
        ("temperature", "slider_temperature", "group_white_balance", 2000.0, 50000.0, TEMPERATURE_NEUTRAL_KELVIN, 0),
        ("tint", "slider_tint", "group_white_balance", -100.0, 100.0, 0.0, 2),
        ("exposure", "slider_exposure", "group_tone", -100.0, 100.0, 0.0, 2),
        ("brightness", "slider_brightness", "group_tone", -100.0, 100.0, 0.0, 2),
        ("contrast", "slider_contrast", "group_tone", -100.0, 100.0, 0.0, 2),
        ("highlights", "slider_highlights", "group_tone", -100.0, 100.0, 0.0, 2),
        ("shadows", "slider_shadows", "group_tone", -100.0, 100.0, 0.0, 2),
        ("whites", "slider_whites", "group_tone", -100.0, 100.0, 0.0, 2),
        ("blacks", "slider_blacks", "group_tone", -100.0, 100.0, 0.0, 2),
        ("texture", "slider_texture", "group_presence", -100.0, 100.0, 0.0, 2),
        ("clarity", "slider_clarity", "group_presence", -100.0, 100.0, 0.0, 2),
        ("dehaze", "slider_dehaze", "group_presence", -100.0, 100.0, 0.0, 2),
        ("vibrance", "slider_vibrance", "group_presence", -100.0, 100.0, 0.0, 2),
        ("saturation", "slider_saturation", "group_presence", -100.0, 100.0, 0.0, 2),
    ]

    def __init__(self, settings: dict | None = None):
        super().__init__()
        self.settings = settings if settings is not None else dict(DEFAULT_SETTINGS)
        self.setWindowTitle(APP_NAME)
        self.setWindowIcon(QIcon(APP_ICON_PATH))
        self.resize(1200, 780)

        self.full_image: np.ndarray | None = None
        self.preview_source: np.ndarray | None = None
        self.live_preview_source: np.ndarray | None = None
        self.rendered_preview: np.ndarray | None = None

        self.thread_pool = QThreadPool(self)
        self.thread_pool.setMaxThreadCount(1)
        self.render_generation = 0
        self.active_drags: set[str] = set()
        self._pending_tasks: list[RenderTask] = []

        self.thumbnail_pool = QThreadPool(self)
        self.thumbnail_pool.setMaxThreadCount(self.settings.get("thumbnail_threads", THUMBNAIL_THREADS))
        self.io_pool = QThreadPool(self)
        self.io_pool.setMaxThreadCount(1)
        self.folder_generation = 0
        self.load_generation = 0
        self.current_files: list[str] = []
        self._thumbnail_items: dict[str, QListWidgetItem] = {}
        self._pending_thumb_tasks: list[ThumbnailTask] = []
        self._pending_load_tasks: list[ImageLoadTask] = []
        self._current_photo_path: str | None = None
        self._thumb_done = 0
        self._thumb_total = 0
        self._loading_mode: str | None = None

        self.edits: dict[str, dict] = load_catalog()
        self.catalog_save_timer = QTimer(self)
        self.catalog_save_timer.setSingleShot(True)
        self.catalog_save_timer.setInterval(CATALOG_SAVE_DEBOUNCE_MS)
        self.catalog_save_timer.timeout.connect(self._save_catalog)

        self._build_menu()

        self.debounce_timer = QTimer(self)
        self.debounce_timer.setSingleShot(True)
        self.debounce_timer.setInterval(DEBOUNCE_MS)
        self.debounce_timer.timeout.connect(self._recompute_and_display)

        self.zoom_mode = "fit"
        self.manual_zoom = 1.0
        self.split_mode = False
        self._display_source_shape: tuple[int, int] | None = None
        self._pending_export_tasks: list[ExportTask] = []

        self.image_label = ImageView(tr("placeholder_open_folder"))
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setMinimumSize(600, 500)
        self.image_label.setStyleSheet("background-color: #141416; color: #8a8a90;")
        self.image_label.wheelZoom.connect(self._on_wheel_zoom)
        self.image_label.dragPanned.connect(self._on_drag_panned)

        self.image_scroll_area = QScrollArea()
        self.image_scroll_area.setWidget(self.image_label)
        self.image_scroll_area.setWidgetResizable(False)
        self.image_scroll_area.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_scroll_area.setStyleSheet("background-color: #141416; border: none;")

        # Split before/after view: original on the left, edited on the right.
        self.after_label = QLabel()
        self.after_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.after_label.setStyleSheet("background-color: #141416;")
        self.before_label = QLabel()
        self.before_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.before_label.setStyleSheet("background-color: #141416;")

        caption_style = "color: #7a7a80; font-size: 10px; font-weight: 600; letter-spacing: 1.5px; padding: 6px;"
        after_caption = QLabel(tr("caption_after"))
        after_caption.setAlignment(Qt.AlignmentFlag.AlignCenter)
        after_caption.setStyleSheet(caption_style)
        before_caption = QLabel(tr("caption_before"))
        before_caption.setAlignment(Qt.AlignmentFlag.AlignCenter)
        before_caption.setStyleSheet(caption_style)

        after_column = QVBoxLayout()
        after_column.addWidget(after_caption)
        after_column.addWidget(self.after_label, stretch=1)
        after_widget = QWidget()
        after_widget.setLayout(after_column)

        before_column = QVBoxLayout()
        before_column.addWidget(before_caption)
        before_column.addWidget(self.before_label, stretch=1)
        before_widget = QWidget()
        before_widget.setLayout(before_column)

        split_layout = QHBoxLayout()
        split_layout.setSpacing(2)
        split_layout.addWidget(before_widget)
        split_layout.addWidget(after_widget)
        self.split_view_widget = QWidget()
        self.split_view_widget.setLayout(split_layout)

        self.image_stack = QStackedWidget()
        self.image_stack.addWidget(self.image_scroll_area)
        self.image_stack.addWidget(self.split_view_widget)

        self.zoom_out_button = QPushButton("−")
        self.zoom_out_button.setFixedSize(28, 28)
        self.zoom_out_button.setStyleSheet("padding: 0px;")
        self.zoom_out_button.clicked.connect(self._zoom_out)

        self.zoom_in_button = QPushButton("+")
        self.zoom_in_button.setFixedSize(28, 28)
        self.zoom_in_button.setStyleSheet("padding: 0px;")
        self.zoom_in_button.clicked.connect(self._zoom_in)

        self.zoom_label = QLabel(tr("zoom_label_fit"))
        self.zoom_label.setFixedWidth(60)
        self.zoom_label.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self.zoom_fit_button = QPushButton(tr("button_zoom_fit"))
        self.zoom_fit_button.clicked.connect(self._set_zoom_fit)

        self.before_after_button = QPushButton(f" {tr('button_before_after')}")
        self.before_after_button.setIcon(make_icon(_draw_compare_icon))
        self.before_after_button.setCheckable(True)
        self.before_after_button.toggled.connect(self._on_before_after_toggled)

        self.before_after_shortcut = QShortcut(QKeySequence(Qt.Key.Key_Backslash), self)
        self.before_after_shortcut.activated.connect(self.before_after_button.toggle)

        viewer_toolbar = QHBoxLayout()
        viewer_toolbar.addWidget(self.zoom_out_button)
        viewer_toolbar.addWidget(self.zoom_label)
        viewer_toolbar.addWidget(self.zoom_in_button)
        viewer_toolbar.addWidget(self.zoom_fit_button)
        viewer_toolbar.addStretch()
        viewer_toolbar.addWidget(self.before_after_button)

        image_column = QVBoxLayout()
        image_column.addWidget(self.image_stack, stretch=1)
        image_column.addLayout(viewer_toolbar)

        self.image_column_widget = QWidget()
        self.image_column_widget.setLayout(image_column)

        self.filmstrip = QListWidget()
        self.filmstrip.setFlow(QListWidget.Flow.LeftToRight)
        self.filmstrip.setWrapping(False)
        self.filmstrip.setViewMode(QListWidget.ViewMode.IconMode)
        self.filmstrip.setIconSize(THUMB_ICON_SIZE)
        self.filmstrip.setResizeMode(QListWidget.ResizeMode.Adjust)
        self.filmstrip.setMovement(QListWidget.Movement.Static)
        self.filmstrip.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.filmstrip.setSpacing(4)
        self.filmstrip.setFixedHeight(THUMB_ICON_SIZE.height() + 40)
        self.filmstrip.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.filmstrip.setStyleSheet("background-color: #19191b; color: #c8c8cc; border: none;")
        self.filmstrip.currentItemChanged.connect(self._on_filmstrip_selection_changed)
        self.filmstrip.itemClicked.connect(self._on_filmstrip_item_clicked)

        self.export_button = QPushButton(f" {tr('button_export')}")
        self.export_button.setIcon(make_icon(_draw_export_icon))
        self.export_button.setEnabled(False)
        self.export_button.clicked.connect(self.export_current)

        self.reset_button = QPushButton()
        self.reset_button.setIcon(make_icon(_draw_reset_icon))
        self.reset_button.setToolTip(tr("button_reset_tooltip"))
        self.reset_button.setFixedSize(32, 32)
        self.reset_button.setStyleSheet("padding: 0px;")
        self.reset_button.clicked.connect(self.reset_sliders)

        self.histogram = HistogramWidget()

        top_buttons = QHBoxLayout()
        top_buttons.setSpacing(8)
        top_buttons.addWidget(self.export_button, stretch=1)
        top_buttons.addWidget(self.reset_button)

        controls = QVBoxLayout()
        controls.setSpacing(4)
        controls.setContentsMargins(16, 14, 16, 14)
        controls.addLayout(top_buttons)
        controls.addSpacing(10)
        controls.addWidget(self.histogram)

        self.slider_controls: dict[str, SliderControl] = {}
        groups: dict[str, QVBoxLayout] = {}

        for key, name_key, group_key, minimum, maximum, default, decimals in self.SLIDER_SPECS:
            if group_key not in groups:
                if groups:
                    controls.addSpacing(10)
                    separator = QFrame()
                    separator.setFixedHeight(1)
                    separator.setStyleSheet("background-color: #303034; border: none;")
                    controls.addWidget(separator)
                section_label = QLabel(tr(group_key).upper())
                section_label.setStyleSheet(
                    "color: #8a8a90; font-size: 10px; font-weight: 600; "
                    "letter-spacing: 1.5px; padding-top: 14px; padding-bottom: 2px;"
                )
                controls.addWidget(section_label)
                group_layout = QVBoxLayout()
                group_layout.setSpacing(12)
                groups[group_key] = group_layout
                controls.addLayout(group_layout)

            control = SliderControl(key, tr(name_key), minimum, maximum, default=default, decimals=decimals)
            control.valueChanged.connect(self._on_slider_value_changed)
            control.sliderPressed.connect(self._on_slider_pressed)
            control.sliderReleased.connect(self._on_slider_released)
            groups[group_key].addWidget(control)
            self.slider_controls[key] = control

        controls.addStretch()

        controls_widget = QWidget()
        controls_widget.setLayout(controls)
        controls_widget.setFixedWidth(260)
        controls_widget.setStyleSheet("background-color: #1b1b1d;")

        scroll_area = QScrollArea()
        scroll_area.setWidget(controls_widget)
        scroll_area.setWidgetResizable(True)
        scroll_area.setFixedWidth(280)
        scroll_area.setStyleSheet("background-color: #1b1b1d;")

        top_layout = QHBoxLayout()
        top_layout.addWidget(self.image_column_widget, stretch=1)
        top_layout.addWidget(scroll_area)

        self.top_widget = QWidget()
        self.top_widget.setLayout(top_layout)

        main_layout = QVBoxLayout()
        main_layout.addWidget(self.top_widget, stretch=1)
        main_layout.addWidget(self.filmstrip)

        central = QWidget()
        central.setLayout(main_layout)
        self.setCentralWidget(central)

        # Parented to top_widget (not the whole window) so the filmstrip stays
        # clickable while a folder's thumbnails are still loading in the background.
        self.loading_overlay = LoadingOverlay(self.top_widget)
        self.loading_overlay.cancelled.connect(self._on_loading_cancelled)
        self.loading_overlay.setGeometry(self.top_widget.rect())

    def _build_menu(self):
        file_menu = self.menuBar().addMenu(tr("menu_file"))

        open_file_action = QAction(make_icon(_draw_file_icon), tr("action_open_file"), self)
        open_file_action.setShortcut("Ctrl+O")
        open_file_action.triggered.connect(self.open_file)
        file_menu.addAction(open_file_action)

        open_folder_action = QAction(make_icon(_draw_folder_icon), tr("action_open_folder"), self)
        open_folder_action.setShortcut("Ctrl+Shift+O")
        open_folder_action.triggered.connect(self.open_folder)
        file_menu.addAction(open_folder_action)

        file_menu.addSeparator()

        self.export_action = QAction(make_icon(_draw_export_icon), tr("action_export"), self)
        self.export_action.setShortcut("Ctrl+E")
        self.export_action.setEnabled(False)
        self.export_action.triggered.connect(self.export_current)
        file_menu.addAction(self.export_action)

        settings_action = QAction(tr("action_settings"), self)
        settings_action.triggered.connect(self.open_settings)
        self.menuBar().addAction(settings_action)

    def open_settings(self):
        dialog = SettingsDialog(self.settings, self.thumbnail_pool, self)
        dialog.exec()

    def _on_slider_value_changed(self, key: str, value: float):
        self.debounce_timer.start()
        self.catalog_save_timer.start()

    def _on_slider_pressed(self, key: str):
        self.active_drags.add(key)

    def _on_slider_released(self, key: str):
        self.active_drags.discard(key)
        self.debounce_timer.start()

    def _apply_params(self, params: dict):
        for key, control in self.slider_controls.items():
            control.set_value(float(params.get(key, control.default)), emit=False)

    def _flush_current_edits(self):
        if self._current_photo_path is None:
            return
        self.edits[self._current_photo_path] = self._current_params()
        self.catalog_save_timer.stop()
        save_catalog(self.edits)

    def _save_catalog(self):
        if self._current_photo_path is not None:
            self.edits[self._current_photo_path] = self._current_params()
        save_catalog(self.edits)

    def _current_params(self) -> dict:
        return {key: control.value() for key, control in self.slider_controls.items()}

    def _default_pictures_dir(self) -> str:
        return QStandardPaths.writableLocation(QStandardPaths.StandardLocation.PicturesLocation)

    def open_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self, tr("dialog_open_file_title"), self._default_pictures_dir(), RAW_EXTENSIONS
        )
        if not path:
            return
        self.open_folder_path(os.path.dirname(path), select_path=path)

    def open_folder(self):
        folder = QFileDialog.getExistingDirectory(self, tr("dialog_open_folder_title"), self._default_pictures_dir())
        if not folder:
            return
        self.open_folder_path(folder)

    def open_folder_path(self, folder: str, select_path: str | None = None):
        files = list_raw_files(folder)
        self.folder_generation += 1
        generation = self.folder_generation
        self.current_files = files
        self._pending_thumb_tasks.clear()
        self._current_photo_path = None

        self.filmstrip.blockSignals(True)
        self.filmstrip.clear()
        self._thumbnail_items = {}

        placeholder = QPixmap(self.filmstrip.iconSize())
        placeholder.fill(QColor("#26262a"))
        placeholder_icon = QIcon(rounded_pixmap(placeholder, THUMB_CORNER_RADIUS))

        self._thumb_done = 0
        self._thumb_total = len(files)
        if files:
            self._loading_mode = "thumbnails"
            self.loading_overlay.start(tr("loading_thumbnails", done=0, total=len(files)), maximum=len(files))

        for path in files:
            item = QListWidgetItem(placeholder_icon, os.path.basename(path))
            item.setData(Qt.ItemDataRole.UserRole, path)
            item.setToolTip(os.path.basename(path))
            self.filmstrip.addItem(item)
            self._thumbnail_items[path] = item

            task = ThumbnailTask(path, generation)
            task.signals.finished.connect(self._on_thumbnail_ready)
            self._pending_thumb_tasks.append(task)
            self.thumbnail_pool.start(task)

        self.filmstrip.blockSignals(False)

        if not files:
            return
        select_index = 0
        if select_path is not None and select_path in files:
            select_index = files.index(select_path)
        self.filmstrip.setCurrentRow(select_index)

    def _cancel_folder_load(self):
        self.folder_generation += 1
        self.thumbnail_pool.clear()
        self.loading_overlay.finish()
        self._loading_mode = None

    def _cancel_image_load(self):
        self.load_generation += 1
        self.loading_overlay.finish()
        self._loading_mode = None

    def _on_loading_cancelled(self):
        if self._loading_mode == "thumbnails":
            self._cancel_folder_load()
        elif self._loading_mode == "image":
            self._cancel_image_load()

    def _on_filmstrip_selection_changed(self, current: QListWidgetItem, previous: QListWidgetItem):
        if current is None:
            return
        self._load_item(current)

    def _on_filmstrip_item_clicked(self, item: QListWidgetItem):
        self._load_item(item)

    def _load_item(self, item: QListWidgetItem):
        path = item.data(Qt.ItemDataRole.UserRole)
        if path == self._current_photo_path:
            return
        self._flush_current_edits()
        self._current_photo_path = path
        self._open_path(path)

    def _on_thumbnail_ready(self, path: str, generation: int, image: np.ndarray | None):
        self._pending_thumb_tasks = [
            t for t in self._pending_thumb_tasks if not (t.path == path and t.generation == generation)
        ]
        if generation != self.folder_generation:
            return

        self._thumb_done += 1
        if self._loading_mode == "thumbnails":
            if self._thumb_done >= self._thumb_total:
                self.loading_overlay.finish()
                self._loading_mode = None
            else:
                self.loading_overlay.set_progress(
                    self._thumb_done, tr("loading_thumbnails", done=self._thumb_done, total=self._thumb_total)
                )

        if image is None:
            return
        item = self._thumbnail_items.get(path)
        if item is None:
            return
        pixmap = rgb_array_to_pixmap(image)
        scaled = pixmap.scaled(
            self.filmstrip.iconSize(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        item.setIcon(QIcon(rounded_pixmap(scaled, THUMB_CORNER_RADIUS)))

    def _open_path(self, path: str):
        self.load_generation += 1
        generation = self.load_generation
        self.export_button.setEnabled(False)
        self.export_action.setEnabled(False)
        self._loading_mode = "image"
        self.loading_overlay.start(tr("loading_image", name=os.path.basename(path)), maximum=0)
        task = ImageLoadTask(path, generation)
        task.signals.finished.connect(self._on_image_loaded)
        self._pending_load_tasks.append(task)
        self.io_pool.start(task)

    def _on_image_loaded(
        self,
        path: str,
        generation: int,
        full_image: np.ndarray | None,
        preview_source: np.ndarray | None,
        live_preview_source: np.ndarray | None,
    ):
        self._pending_load_tasks = [
            t for t in self._pending_load_tasks if not (t.path == path and t.generation == generation)
        ]
        if generation != self.load_generation:
            return
        if self._loading_mode == "image":
            self.loading_overlay.finish()
            self._loading_mode = None
        if full_image is None:
            return
        self.full_image = full_image
        self.preview_source = preview_source
        self.live_preview_source = live_preview_source
        self.setWindowTitle(f"{APP_NAME} — {os.path.basename(path)}")
        self.export_button.setEnabled(True)
        self.export_action.setEnabled(True)
        saved_params = self.edits.get(path)
        if saved_params:
            saved_params = dict(saved_params)
            # Catalog entries saved before temperature became an absolute Kelvin value
            # stored a small delta (-100..100); treat those as "no saved temperature".
            if saved_params.get("temperature", TEMPERATURE_NEUTRAL_KELVIN) < 1000:
                saved_params["temperature"] = TEMPERATURE_NEUTRAL_KELVIN
            self._apply_params(saved_params)
        else:
            self.reset_sliders(recompute=False)
        self._recompute_and_display()

    def reset_sliders(self, recompute: bool = True):
        for control in self.slider_controls.values():
            control.reset()
        if recompute:
            self._recompute_and_display()

    def _recompute_and_display(self):
        if self.preview_source is None:
            return
        use_live = self.settings.get("fast_preview", True) and bool(self.active_drags)
        source = self.live_preview_source if use_live else self.preview_source
        params = self._current_params()
        self.render_generation += 1
        task = RenderTask(self.render_generation, source, params)
        task.signals.finished.connect(self._on_render_finished)
        self._pending_tasks.append(task)
        self.thread_pool.start(task)

    def _on_render_finished(self, generation: int, result: np.ndarray):
        self._pending_tasks = [t for t in self._pending_tasks if t.generation != generation]
        if generation != self.render_generation:
            return
        self.rendered_preview = result
        self._display_current_render()
        self._update_current_thumbnail()
        self.histogram.set_image(result)

    def _update_current_thumbnail(self):
        if self._current_photo_path is None or self.rendered_preview is None:
            return
        item = self._thumbnail_items.get(self._current_photo_path)
        if item is None:
            return
        pixmap = rgb_array_to_pixmap(self.rendered_preview)
        scaled = pixmap.scaled(
            self.filmstrip.iconSize(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        item.setIcon(QIcon(rounded_pixmap(scaled, THUMB_CORNER_RADIUS)))

    def _display_current_render(self):
        if self.split_mode:
            self._display_split_view()
        else:
            self._display_single_view()

    def _display_single_view(self):
        source = self.rendered_preview
        if source is None:
            return
        self._display_source_shape = source.shape[:2]
        pixmap = rgb_array_to_pixmap(source)
        if self.zoom_mode == "fit":
            scaled = pixmap.scaled(
                self.image_scroll_area.viewport().size(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
        else:
            target_size = QSize(int(pixmap.width() * self.manual_zoom), int(pixmap.height() * self.manual_zoom))
            scaled = pixmap.scaled(
                target_size, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation
            )
        self.image_label.setPixmap(scaled)
        self.image_label.resize(scaled.size())

    def _display_split_view(self):
        if self.rendered_preview is None or self.preview_source is None:
            return
        after_pixmap = rgb_array_to_pixmap(self.rendered_preview)
        before_pixmap = rgb_array_to_pixmap(self.preview_source)
        self.after_label.setPixmap(
            after_pixmap.scaled(
                self.after_label.size(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
        )
        self.before_label.setPixmap(
            before_pixmap.scaled(
                self.before_label.size(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
        )

    def _effective_zoom(self) -> float:
        if self.zoom_mode == "manual":
            return self.manual_zoom
        pixmap = self.image_label.pixmap()
        if pixmap is None or pixmap.isNull() or not self._display_source_shape:
            return 1.0
        native_width = self._display_source_shape[1]
        return pixmap.width() / native_width if native_width else 1.0

    def _update_zoom_label(self):
        if self.zoom_mode == "fit":
            self.zoom_label.setText(tr("zoom_label_fit"))
        else:
            self.zoom_label.setText(f"{round(self.manual_zoom * 100)}%")

    def _set_zoom(self, zoom: float, anchor_viewport_pos: QPoint | None = None):
        zoom = max(self.MIN_ZOOM, min(self.MAX_ZOOM, zoom))
        h_bar = self.image_scroll_area.horizontalScrollBar()
        v_bar = self.image_scroll_area.verticalScrollBar()

        old_zoom = self._effective_zoom()
        content_x = content_y = ratio = None
        if anchor_viewport_pos is not None and old_zoom:
            content_x = h_bar.value() + anchor_viewport_pos.x()
            content_y = v_bar.value() + anchor_viewport_pos.y()
            ratio = zoom / old_zoom

        self.zoom_mode = "manual"
        self.manual_zoom = zoom
        self._display_current_render()
        self._update_zoom_label()

        if ratio is not None:
            h_bar.setValue(int(content_x * ratio - anchor_viewport_pos.x()))
            v_bar.setValue(int(content_y * ratio - anchor_viewport_pos.y()))

    def _set_zoom_fit(self):
        self.zoom_mode = "fit"
        self._display_current_render()
        self._update_zoom_label()

    def _zoom_in(self):
        center = self.image_scroll_area.viewport().rect().center()
        self._set_zoom(self._effective_zoom() * self.ZOOM_STEP, anchor_viewport_pos=center)

    def _zoom_out(self):
        center = self.image_scroll_area.viewport().rect().center()
        self._set_zoom(self._effective_zoom() / self.ZOOM_STEP, anchor_viewport_pos=center)

    def _on_wheel_zoom(self, delta: int, global_pos: QPoint):
        if self.rendered_preview is None and self.preview_source is None:
            return
        viewport = self.image_scroll_area.viewport()
        cursor_pos = viewport.mapFromGlobal(global_pos)
        if not viewport.rect().contains(cursor_pos):
            return
        factor = self.ZOOM_STEP if delta > 0 else 1.0 / self.ZOOM_STEP
        self._set_zoom(self._effective_zoom() * factor, anchor_viewport_pos=cursor_pos)

    def _on_drag_panned(self, delta: QPoint):
        h_bar = self.image_scroll_area.horizontalScrollBar()
        v_bar = self.image_scroll_area.verticalScrollBar()
        h_bar.setValue(h_bar.value() - delta.x())
        v_bar.setValue(v_bar.value() - delta.y())

    def _on_before_after_toggled(self, checked: bool):
        self.split_mode = checked
        self.image_stack.setCurrentWidget(self.split_view_widget if checked else self.image_scroll_area)
        self.zoom_out_button.setEnabled(not checked)
        self.zoom_in_button.setEnabled(not checked)
        self.zoom_fit_button.setEnabled(not checked)
        self._display_current_render()

    def export_current(self):
        if self._current_photo_path is None:
            return
        options_dialog = ExportOptionsDialog(self)
        if options_dialog.exec() != QDialog.DialogCode.Accepted:
            return
        image_format = options_dialog.selected_format()
        quality = options_dialog.selected_quality()
        extension = options_dialog.selected_extension()

        base_name = os.path.splitext(os.path.basename(self._current_photo_path))[0]
        default_path = os.path.join(self._default_pictures_dir(), f"{base_name}_edit.{extension}")
        dest_path, _ = QFileDialog.getSaveFileName(
            self, tr("export_save_dialog_title"), default_path, f"{image_format} (*.{extension})"
        )
        if not dest_path:
            return
        params = self._current_params()
        self._loading_mode = "export"
        self.loading_overlay.start(tr("loading_exporting", name=os.path.basename(dest_path)), maximum=0, cancellable=False)
        self.export_button.setEnabled(False)
        self.export_action.setEnabled(False)
        task = ExportTask(self._current_photo_path, dest_path, params, image_format, quality)
        task.signals.finished.connect(self._on_export_finished)
        self._pending_export_tasks.append(task)
        self.io_pool.start(task)

    def _on_export_finished(self, success: bool, message: str):
        self._pending_export_tasks.clear()
        if self._loading_mode == "export":
            self.loading_overlay.finish()
            self._loading_mode = None
        self.export_button.setEnabled(self._current_photo_path is not None)
        self.export_action.setEnabled(self._current_photo_path is not None)
        if success:
            QMessageBox.information(self, tr("export_success_title"), tr("export_success_message", path=message))
        else:
            QMessageBox.warning(self, tr("export_success_title"), tr("export_failure_message", error=message))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._display_current_render()
        self.loading_overlay.setGeometry(self.top_widget.rect())

    def closeEvent(self, event):
        self._flush_current_edits()
        super().closeEvent(event)


APP_STYLESHEET = """
QMainWindow, QWidget {
    background-color: #1e1e20;
    color: #e6e6e8;
    font-family: "Segoe UI", sans-serif;
    font-size: 12.5px;
}

QMenuBar {
    background-color: #1e1e20;
    color: #cfcfd2;
    border-bottom: 1px solid #2c2c2f;
    padding: 2px;
}
QMenuBar::item {
    background: transparent;
    padding: 4px 10px;
    border-radius: 4px;
}
QMenuBar::item:selected {
    background-color: #2f2f33;
}
QMenu {
    background-color: #232326;
    color: #e6e6e8;
    border: 1px solid #34343a;
    border-radius: 8px;
    padding: 4px;
}
QMenu::item {
    padding: 6px 24px 6px 12px;
    border-radius: 4px;
}
QMenu::item:selected {
    background-color: #0a84ff;
    color: white;
}
QMenu::item:disabled {
    color: #6b6b70;
}
QMenu::separator {
    height: 1px;
    background: #34343a;
    margin: 4px 8px;
}

QPushButton {
    background-color: #2c2c30;
    color: #e6e6e8;
    border: 1px solid #38383d;
    border-radius: 7px;
    padding: 6px 14px;
}
QPushButton:hover {
    background-color: #343439;
}
QPushButton:pressed {
    background-color: #26262a;
}
QPushButton:disabled {
    color: #6b6b70;
    background-color: #232326;
    border-color: #2c2c30;
}
QPushButton:checked {
    background-color: #0a84ff;
    border-color: #0a84ff;
    color: white;
}

QSlider::groove:horizontal {
    height: 1px;
    background: #38383d;
    border-radius: 0px;
}
QSlider::sub-page:horizontal {
    background: #e8e8ea;
    border-radius: 0px;
}
QSlider::add-page:horizontal {
    background: #38383d;
    border-radius: 0px;
}
QSlider::handle:horizontal {
    background: #f2f2f2;
    width: 10px;
    height: 10px;
    margin: -4.5px 0;
    border-radius: 5px;
}
QSlider::handle:horizontal:hover {
    background: #ffffff;
}
QSlider::handle:horizontal:disabled {
    background: #5a5a5f;
}

QScrollArea {
    border: none;
}
QScrollBar:vertical {
    background: transparent;
    width: 11px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background: #3a3a3f;
    border-radius: 4px;
    min-height: 24px;
}
QScrollBar::handle:vertical:hover {
    background: #4a4a50;
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0;
}
QScrollBar:horizontal {
    background: transparent;
    height: 11px;
}
QScrollBar::handle:horizontal {
    background: #3a3a3f;
    border-radius: 4px;
    min-width: 24px;
}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
    width: 0;
}

QListWidget {
    border: none;
    outline: none;
}
QListWidget::item:selected {
    background-color: #2b3f57;
    border-radius: 8px;
}

QDialog {
    background-color: #1e1e20;
}
QComboBox, QSpinBox, QLineEdit {
    background-color: #2c2c30;
    border: 1px solid #38383d;
    border-radius: 6px;
    padding: 4px 8px;
    color: #e6e6e8;
}
QComboBox QAbstractItemView {
    background-color: #232326;
    color: #e6e6e8;
    selection-background-color: #0a84ff;
    border: 1px solid #34343a;
}

QProgressBar {
    background-color: #38383d;
    border: none;
    border-radius: 2px;
    text-align: center;
    color: #e6e6e8;
}
QProgressBar::chunk {
    background-color: #f2f2f2;
    border-radius: 2px;
}

QToolTip {
    background-color: #232326;
    color: #e6e6e8;
    border: 1px solid #34343a;
    padding: 4px;
}
"""


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setStyleSheet(APP_STYLESHEET)
    settings = load_settings()
    set_language(resolve_language(settings.get("language", "auto")))
    window = MainWindow(settings)
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
