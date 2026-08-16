import sys

import numpy as np
import rawpy
from PIL import Image
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QScrollArea,
    QSlider,
    QVBoxLayout,
    QWidget,
)
from scipy.ndimage import gaussian_filter, minimum_filter, uniform_filter

RAW_EXTENSIONS = "RAW Files (*.cr2 *.cr3 *.nef *.arw *.dng *.raf *.orf *.rw2)"
PREVIEW_MAX_DIM = 1600
DEBOUNCE_MS = 25


def load_raw_as_rgb(path: str) -> np.ndarray:
    with rawpy.imread(path) as raw:
        rgb = raw.postprocess(use_camera_wb=True, output_bps=8)
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


def apply_white_balance(image: np.ndarray, temperature: float, tint: float) -> np.ndarray:
    if temperature == 0 and tint == 0:
        return image
    r_gain = 1.0 + (temperature / 100.0) * 0.3
    b_gain = 1.0 - (temperature / 100.0) * 0.3
    g_gain = 1.0 - (tint / 100.0) * 0.2
    image[..., 0] *= r_gain
    image[..., 1] *= g_gain
    image[..., 2] *= b_gain
    return image


def apply_brightness_contrast(image: np.ndarray, brightness: float, contrast: float) -> np.ndarray:
    if brightness == 0 and contrast == 0:
        return image
    contrast_factor = 1.0 + contrast / 100.0
    return (image - 127.5) * contrast_factor + 127.5 + brightness


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
    img = apply_brightness_contrast(img, params["brightness"], params["contrast"])
    img = apply_local_contrast(img, params["texture"], radius=3)
    img = apply_local_contrast(img, params["clarity"], radius=25, protect_midtones=True)
    img = apply_dehaze(img, params["dehaze"])
    return np.clip(img, 0, 255).astype(np.uint8)


def rgb_array_to_pixmap(image: np.ndarray) -> QPixmap:
    height, width, _ = image.shape
    contiguous = np.ascontiguousarray(image)
    qimage = QImage(contiguous.data, width, height, width * 3, QImage.Format.Format_RGB888)
    return QPixmap.fromImage(qimage.copy())


class MainWindow(QMainWindow):
    SLIDER_SPECS = [
        # (key, label, group, min, max, default, protect_midtones-only-relevant-for-render)
        ("temperature", "Temperatura", "Balanço de Branco"),
        ("tint", "Matiz", "Balanço de Branco"),
        ("brightness", "Brilho", "Tom"),
        ("contrast", "Contraste", "Tom"),
        ("texture", "Textura", "Presença"),
        ("clarity", "Claridade", "Presença"),
        ("dehaze", "Remoção de Neblina", "Presença"),
    ]

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Darkmoon")
        self.resize(1200, 780)

        self.full_image: np.ndarray | None = None
        self.preview_source: np.ndarray | None = None
        self.rendered_preview: np.ndarray | None = None

        self.debounce_timer = QTimer(self)
        self.debounce_timer.setSingleShot(True)
        self.debounce_timer.setInterval(DEBOUNCE_MS)
        self.debounce_timer.timeout.connect(self._recompute_and_display)

        self.image_label = QLabel("Abra um arquivo RAW para começar")
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setMinimumSize(600, 500)
        self.image_label.setStyleSheet("background-color: #202020; color: #aaa;")

        self.open_button = QPushButton("Abrir RAW...")
        self.open_button.clicked.connect(self.open_file)

        self.reset_button = QPushButton("Redefinir ajustes")
        self.reset_button.clicked.connect(self.reset_sliders)

        self.sliders: dict[str, QSlider] = {}
        self.value_labels: dict[str, QLabel] = {}
        groups: dict[str, QVBoxLayout] = {}

        controls = QVBoxLayout()
        controls.addWidget(self.open_button)
        controls.addWidget(self.reset_button)

        for key, name, group_name in self.SLIDER_SPECS:
            if group_name not in groups:
                group_box = QGroupBox(group_name)
                group_layout = QVBoxLayout()
                group_box.setLayout(group_layout)
                groups[group_name] = group_layout
                controls.addWidget(group_box)

            label = QLabel(f"{name}: 0")
            slider = self._make_slider(-100, 100, 0)
            slider.valueChanged.connect(lambda value, k=key, n=name: self._on_slider_changed(k, n, value))

            groups[group_name].addWidget(label)
            groups[group_name].addWidget(slider)

            self.sliders[key] = slider
            self.value_labels[key] = label

        controls.addStretch()

        controls_widget = QWidget()
        controls_widget.setLayout(controls)
        controls_widget.setFixedWidth(240)

        scroll_area = QScrollArea()
        scroll_area.setWidget(controls_widget)
        scroll_area.setWidgetResizable(True)
        scroll_area.setFixedWidth(260)

        layout = QHBoxLayout()
        layout.addWidget(scroll_area)
        layout.addWidget(self.image_label, stretch=1)

        central = QWidget()
        central.setLayout(layout)
        self.setCentralWidget(central)

    def _make_slider(self, minimum: int, maximum: int, default: int) -> QSlider:
        slider = QSlider(Qt.Orientation.Horizontal)
        slider.setMinimum(minimum)
        slider.setMaximum(maximum)
        slider.setValue(default)
        return slider

    def _on_slider_changed(self, key: str, name: str, value: int):
        self.value_labels[key].setText(f"{name}: {value}")
        self.debounce_timer.start()

    def _current_params(self) -> dict:
        return {key: float(slider.value()) for key, slider in self.sliders.items()}

    def open_file(self):
        path, _ = QFileDialog.getOpenFileName(self, "Abrir arquivo RAW", "", RAW_EXTENSIONS)
        if not path:
            return
        self.full_image = load_raw_as_rgb(path)
        self.preview_source = make_preview(self.full_image)
        self.reset_sliders(recompute=False)
        self._recompute_and_display()

    def reset_sliders(self, recompute: bool = True):
        for key, slider in self.sliders.items():
            slider.blockSignals(True)
            slider.setValue(0)
            slider.blockSignals(False)
        for key, name, _ in self.SLIDER_SPECS:
            self.value_labels[key].setText(f"{name}: 0")
        if recompute:
            self._recompute_and_display()

    def _recompute_and_display(self):
        if self.preview_source is None:
            return
        params = self._current_params()
        self.rendered_preview = render(self.preview_source, params)
        self._display_current_render()

    def _display_current_render(self):
        if self.rendered_preview is None:
            return
        pixmap = rgb_array_to_pixmap(self.rendered_preview)
        scaled = pixmap.scaled(
            self.image_label.size(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        self.image_label.setPixmap(scaled)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._display_current_render()


def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
