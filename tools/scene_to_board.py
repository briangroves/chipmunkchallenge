#!/usr/bin/env python3
"""Turn a generated scene (a cartoon subject on a backdrop that suits it) into a 40x40 board in the game's palette.

    tools/.venv/bin/python tools/scene_to_board.py IMAGE --out board.json [--png board.png]

Unlike image_to_board.py (clipart cut out and pasted on a stock backdrop), the backdrop here comes from the picture
itself, so it always fits the subject, and the picture's own shading and outlines carry over. Steps:
  1. Find the subject (rembg) and frame it: a square crop with the subject centered and filling most of the board.
     A subject cut off by the picture's edge is reported (`cut`), so callers can drop the picture.
  2. Shrink in two steps: average down to 80x80, then each board block takes the darkest of its four pixels if it's
     dark (so outlines, eyes and smiles survive) or else their average (so colors and shading stay smooth).
  3. Snap each block to the nearest palette color (in Lab).
This beat a converter with hand-written rules for eyes, lines, shading and dithering: those added noise, while the
generated art already has clean outlines and shading to keep.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from image_to_board import PALETTE  # noqa: E402

N = 40
KEYS = list(PALETTE)
PAL = np.array([[(v >> 16) & 255, (v >> 8) & 255, v & 255] for v in PALETTE.values()], float)
FILL = 0.78           # the subject's longer side spans this share of the board, leaving room for the backdrop
_session = None


def lab(rgb):
    """sRGB (0-255, ...x3) to CIE Lab."""
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


PAL_LAB = lab(PAL)


def nearest(lab_px, allowed=None):
    """Index of the nearest palette color for each pixel (chroma weighted a little more, so a pale colored area
    doesn't drift to grey)."""
    d = lab_px[..., None, :] - PAL_LAB
    d = d[..., 0] ** 2 + 1.3 * (d[..., 1] ** 2 + d[..., 2] ** 2)
    if allowed is not None:
        d[..., [i for i in range(len(KEYS)) if i not in allowed]] = np.inf
    return d.argmin(-1)


def subject_mask(img):
    global _session
    from rembg import new_session, remove
    if _session is None:
        _session = new_session("isnet-general-use")
    alpha = np.asarray(remove(img, session=_session, only_mask=True), float) / 255
    mask = alpha > 0.5
    # Keep the biggest piece (plus pieces nearly as big): stray bits of backdrop the cutter grabbed are dropped.
    lab_, n = ndimage.label(mask)
    if n > 1:
        sizes = ndimage.sum(mask, lab_, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= 0.25 * sizes.max()]
        mask = np.isin(lab_, keep)
    return ndimage.binary_fill_holes(mask)


def frame(img, mask, fill=FILL):
    """A square crop with the subject centered and filling FILL of the board. Returns the crop box and whether the
    subject touches the picture's edge (cut off)."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    edge = 3
    cut = y0 < edge or x0 < edge or x1 > w - edge or (y1 > h - edge and (x1 - x0) < 0.8 * w)
    side = max(y1 - y0, x1 - x0) / fill
    side = min(side, w, h)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    # Stand a subject that reaches the ground a little low, so it doesn't float.
    left = int(round(min(max(cx - side / 2, 0), w - side)))
    top = int(round(min(max(cy - side / 2 + 0.03 * side, 0), h - side)))
    return (left, top, int(side)), bool(cut), (y1 - y0, x1 - x0)


def shrink(crop):
    """The crop as 40x40 RGB: average down to 80x80, then per block the darkest of its 2x2 pixels when it's dark
    (keeps thin dark lines and eyes), else the 2x2 average."""
    mid = np.asarray(crop.resize((2 * N, 2 * N), Image.BOX), float)
    quads = mid.reshape(N, 2, N, 2, 3).transpose(0, 2, 1, 3, 4).reshape(N, N, 4, 3)
    lum = quads.sum(-1)
    darkest = np.take_along_axis(quads, lum.argmin(-1)[..., None, None], 2)[:, :, 0]
    return np.where((lum.min(-1) < 150)[..., None], darkest, quads.mean(2))


def convert(path, fill=FILL):
    """Board rows and facts about the conversion (cut off, subject size, colors), or (None, error)."""
    img = Image.open(path).convert("RGB")
    mask = subject_mask(img)
    if mask.sum() < 0.02 * mask.size:
        return None, dict(error="no subject found")
    (left, top, side), cut, (sh, sw) = frame(img, mask, fill)
    idx = nearest(lab(shrink(img.crop((left, top, left + side, top + side)))))
    rows = ["".join(KEYS[i] for i in row) for row in idx]
    subj = np.asarray(Image.fromarray(mask[top:top + side, left:left + side]).resize((N, N), Image.BOX)) > 0
    info = dict(fill=fill, cut=cut, subject=round(float(subj.mean()), 3), colors=len(set("".join(rows))),
                aspect=round(sw / sh, 2), touches=bool(subj[0].any() or subj[-1].any() or subj[:, 0].any()
                                                       or subj[:, -1].any()))
    return rows, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--out")
    ap.add_argument("--png")
    a = ap.parse_args()
    rows, info = convert(a.image)
    print(json.dumps(info))
    if rows is None:
        sys.exit(1)
    if a.out:
        json.dump({"rows": rows, "info": info}, open(a.out, "w"))
    if a.png:
        import check_boards
        check_boards.render_png(rows, a.png, z=12)
    print("\n".join(rows))


if __name__ == "__main__":
    main()
