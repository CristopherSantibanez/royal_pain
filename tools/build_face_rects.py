"""Calcula dónde está la cara en cada retrato de cuerpo entero.

Uso:  python tools/build_face_rects.py [--sheet salida.png]
Escribe scripts/resources/face_rects.gd: ruta res:// -> [x, y, lado] (recorte cuadrado en píxeles).
Es un script de datos (no JSON) para que viaje en el juego exportado. El juego lo usa para mostrar
solo la cara (Character.get_face()). Si un recorte sale mal se puede corregir a mano en ese archivo;
con --sheet se genera una hoja para revisarlos todos.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "scripts", "resources", "face_rects.gd")
ALPHA_MIN = 128
HEAD_RATIO = 0.135      # alto de la cabeza respecto a la figura (estilo de los retratos)
FACE_SCALE = 1.55       # el recorte cubre algo más que la cabeza (pelo y cuello)
MIN_ROW_PIXELS = 12


def face_rect(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    alpha = im.getchannel("A").point(lambda a: 255 if a >= ALPHA_MIN else 0)
    px = alpha.load()
    rows = []
    for y in range(h):
        xs = [x for x in range(0, w, 2) if px[x, y]]
        rows.append(xs)
    top = next((y for y, xs in enumerate(rows) if len(xs) >= MIN_ROW_PIXELS // 2), 0)
    bottom = max((y for y, xs in enumerate(rows) if xs), default=h - 1)
    head_h = max(40, int((bottom - top) * HEAD_RATIO))
    # Centro horizontal de la cabeza: mediana de los píxeles opacos de la franja de la cabeza.
    band = []
    for y in range(top + head_h // 4, min(h, top + head_h)):
        band.extend(rows[y])
    band.sort()
    cx = band[len(band) // 2] if band else w // 2
    side = int(head_h * FACE_SCALE)
    cy = top + int(head_h * 0.62)
    x = max(0, min(w - side, cx - side // 2))
    y = max(0, min(h - side, cy - side // 2))
    return [x, y, side]


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "assets", "portraits", "**", "*.png"), recursive=True))
    rects = {}
    for f in files:
        rel = "res://" + os.path.relpath(f, ROOT).replace("\\", "/")
        rects[rel] = face_rect(f)
    lines = ["extends RefCounted",
             "# Generado por tools/build_face_rects.py: recorte de la cara de cada retrato [x, y, lado].",
             "", "const RECTS := {"]
    for path, (x, y, side) in rects.items():
        lines.append('\t"%s": [%d, %d, %d],' % (path, x, y, side))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print("Caras calculadas:", len(rects), "->", OUT)
    if "--sheet" in sys.argv:
        out = sys.argv[sys.argv.index("--sheet") + 1]
        cols, size = 12, 96
        sheet = Image.new("RGB", (cols * size, ((len(files) + cols - 1) // cols) * size), (40, 40, 40))
        for i, f in enumerate(files):
            x, y, s = rects["res://" + os.path.relpath(f, ROOT).replace("\\", "/")]
            face = Image.open(f).convert("RGBA").crop((x, y, x + s, y + s)).resize((size, size))
            bg = Image.new("RGB", (size, size), (40, 40, 40))
            bg.paste(face, (0, 0), face)
            sheet.paste(bg, ((i % cols) * size, (i // cols) * size))
        sheet.save(out)
        print("Hoja de revisión:", out)


if __name__ == "__main__":
    main()
