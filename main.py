import sys

import numpy as np
import rawpy
from PySide6.QtCore import Qt
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QSlider,
    QVBoxLayout,
    QWidget,
)

RAW_EXTENSIONS = "RAW Files (*.cr2 *.cr3 *.nef *.arw *.dng *.raf *.orf *.rw2)"


def load_raw_as_rgb(path: str) -> np.ndarray:
    with rawpy.imread(path) as raw:
        rgb = raw.postprocess(use_camera_wb=True, output_bps=8)
    return rgb


def apply_brightness_contrast(image: np.ndarray, brightness: float, contrast: float) -> np.ndarray:
    img = image.astype(np.float32)
    img = (img - 127.5) * contrast + 127.5 + brightness
    return np.clip(img, 0, 255).astype(np.uint8)


def rgb_array_to_pixmap(image: np.ndarray) -> QPixmap:
    height, width, _ = image.shape
    contiguous = np.ascontiguousarray(image)
    qimage = QImage(contiguous.data, width, height, width * 3, QImage.Format.Format_RGB888)
    return QPixmap.fromImage(qimage.copy())


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Darkmoon")
        self.resize(1100, 750)

        self.original_image: np.ndarray | None = None

        self.image_label = QLabel("Abra um arquivo RAW para começar")
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setMinimumSize(600, 500)
        self.image_label.setStyleSheet("background-color: #202020; color: #aaa;")

        self.open_button = QPushButton("Abrir RAW...")
        self.open_button.clicked.connect(self.open_file)

        self.brightness_slider = self._make_slider(-100, 100, 0)
        self.brightness_slider.valueChanged.connect(self.update_preview)

        self.contrast_slider = self._make_slider(-100, 100, 0)
        self.contrast_slider.valueChanged.connect(self.update_preview)

        controls = QVBoxLayout()
        controls.addWidget(self.open_button)
        controls.addWidget(QLabel("Brilho"))
        controls.addWidget(self.brightness_slider)
        controls.addWidget(QLabel("Contraste"))
        controls.addWidget(self.contrast_slider)
        controls.addStretch()

        controls_widget = QWidget()
        controls_widget.setLayout(controls)
        controls_widget.setFixedWidth(220)

        layout = QHBoxLayout()
        layout.addWidget(controls_widget)
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

    def open_file(self):
        path, _ = QFileDialog.getOpenFileName(self, "Abrir arquivo RAW", "", RAW_EXTENSIONS)
        if not path:
            return
        self.original_image = load_raw_as_rgb(path)
        self.brightness_slider.setValue(0)
        self.contrast_slider.setValue(0)
        self.update_preview()

    def update_preview(self):
        if self.original_image is None:
            return
        brightness = float(self.brightness_slider.value())
        contrast = 1.0 + (self.contrast_slider.value() / 100.0)
        edited = apply_brightness_contrast(self.original_image, brightness, contrast)
        pixmap = rgb_array_to_pixmap(edited)
        scaled = pixmap.scaled(
            self.image_label.size(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        self.image_label.setPixmap(scaled)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.update_preview()


def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
