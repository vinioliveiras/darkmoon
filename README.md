# Darkmoon

Editor de fotos RAW para Windows (MVP inicial), inspirado no Lightroom.

## Stack

- Python + PySide6 (Qt) para a interface
- rawpy (LibRaw) para decodificar arquivos RAW
- NumPy para os ajustes de imagem

## Funcionalidades atuais

- Abrir arquivos RAW (.CR2, .CR3, .NEF, .ARW, .DNG, .RAF, .ORF, .RW2)
- Ajuste de brilho e contraste com preview ao vivo

## Como rodar

```
python -m venv venv
venv\Scripts\activate
pip install rawpy numpy pillow pyside6
python main.py
```
