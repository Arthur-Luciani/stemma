"""QR code do endereço do Stemma em BMP, para a tela final do instalador.

Uso: python qr.py <url> <saida.bmp>

Roda com o Python da release instalada. O `segno` (QR em Python puro) vem como wheel ao lado
deste arquivo e é importado direto do .whl (zipimport), sem instalar nada.
"""

import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = sorted(str(wheel) for wheel in HERE.glob("segno-*.whl"))

import segno  # noqa: E402

SCALE = 5  # pixels por módulo
BORDER = 4  # zona de silêncio, em módulos (mínimo da norma)
# Tokens --qr-dark (#121416) e --qr-light (#f4f2ee), em BGR como o BMP guarda.
DARK = bytes((0x16, 0x14, 0x12))
LIGHT = bytes((0xEE, 0xF2, 0xF4))


def to_bmp(matrix: list[list[bool]], scale: int, border: int) -> bytes:
    """BMP 24 bits, de baixo para cima, com as linhas alinhadas em 4 bytes."""
    modules = len(matrix) + 2 * border
    size = modules * scale
    row_bytes = (size * 3 + 3) & ~3
    rows = []
    for y in range(size - 1, -1, -1):
        my = y // scale - border
        row = bytearray()
        for x in range(size):
            mx = x // scale - border
            dark = 0 <= my < len(matrix) and 0 <= mx < len(matrix) and matrix[my][mx]
            row += DARK if dark else LIGHT
        row += b"\x00" * (row_bytes - len(row))
        rows.append(bytes(row))
    pixels = b"".join(rows)
    header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, size, size, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    return header + info + pixels


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(f"{__doc__}\n")
        return 2
    url, dest = sys.argv[1], sys.argv[2]
    qr = segno.make(url, error="m", boost_error=False)
    matrix = [[bool(cell) for cell in row] for row in qr.matrix]
    Path(dest).write_bytes(to_bmp(matrix, SCALE, BORDER))
    sys.stdout.write(f"QR code ({qr.designator}) em {dest}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
