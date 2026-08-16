# Darkmoon

Editor de fotos RAW para Windows (MVP inicial), inspirado no Lightroom.

## Stack

- Python + PySide6 (Qt) para a interface
- rawpy (LibRaw) para decodificar arquivos RAW
- NumPy + SciPy para os ajustes de imagem

## Funcionalidades atuais

- Abrir arquivos RAW (.CR2, .CR3, .NEF, .ARW, .DNG, .RAF, .ORF, .RW2)
- Balanço de branco (temperatura e matiz)
- Tom (brilho e contraste)
- Presença (textura, claridade e remoção de neblina)
- Preview ao vivo (renderizado sobre uma versão reduzida da imagem, até 1600px, para manter a edição fluida)

## Como rodar

```
python -m venv venv
venv\Scripts\activate
pip install rawpy numpy pillow pyside6 scipy
python main.py
```
