#!/usr/bin/env python3
"""Turn an illustration into a 40x40 Chipmunk Challenge picture (rows of palette letters).

    python3 -I tools/image_to_board.py IMAGE --name "Fox" --out board.json

Steps: read the image (via macOS `sips`, no Python packages needed), cut out the plain background (the color in the
corners), crop to the subject, shrink it into the lower part of the board so it stands on the grass, give each block
the palette color most of its pixels are closest to, add the game's dark outline, then paint a backdrop around it:
sky, a distant ridge, grass, and one big shaded cloud placed in open sky, away from the subject.

This is a first cut of the import pipeline: one subject on one generated backdrop. The board still has to pass the
game's builder, and a person should look at it before it ships.
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import tempfile

N = 40
PALETTE = {
    "R": 0xE53935, "O": 0xFB8C00, "Y": 0xFDD835, "G": 0x43A047, "B": 0x1E88E5, "V": 0x8E24AA,
    "P": 0xF48FB1, "N": 0x795548, "W": 0xF5F5F5, "K": 0x263238, "T": 0xD2B48C, "A": 0x9E9E9E,
    "L": 0x9CCC65, "D": 0x1B5E20, "M": 0x8E1B1B, "C": 0x81D4FA, "U": 0x283593, "I": 0xB39DDB,
    # In-between shades, for shadows, highlights and soft skies.
    "Q": 0xE65100, "J": 0xFFB74D, "H": 0xB3E5FC, "E": 0x4E342E, "S": 0xD81B60, "Z": 0xFFF59D, "X": 0xD7CCC8,
}
RGB = {k: ((v >> 16) & 255, (v >> 8) & 255, v & 255) for k, v in PALETTE.items()}
# Colors the subject's source is matched against: the 18 standard ones (blue eyes need blue). The in-between shades
# are kept for shading, which works from these base colors; the backdrop is chosen to contrast with the subject.
SHADES = ("Q", "J", "H", "E", "S", "Z", "X")
SUBJECT = [k for k in PALETTE if k not in SHADES]
NEUTRAL = ["W", "A", "K"]


def dist(a, b):
    """Perceptual ("redmean") color distance."""
    rm = (a[0] + b[0]) / 2
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db


def nearest(c, keys):
    return min(keys, key=lambda k: dist(c, RGB[k]))


def load(path, width=400):
    """Pixels as rows of (r, g, b), read through a 24-bit BMP made by sips."""
    with tempfile.TemporaryDirectory() as d:
        bmp = os.path.join(d, "x.bmp")
        subprocess.run(["sips", "-s", "format", "bmp", "-Z", str(width), path, "--out", bmp],
                       check=True, capture_output=True)
        data = open(bmp, "rb").read()
    off = struct.unpack_from("<I", data, 10)[0]
    w, h = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    step = bpp // 8
    stride = (w * step + 3) & ~3
    flip = h > 0
    h = abs(h)
    rows = []
    for y in range(h):
        sy = h - 1 - y if flip else y
        base = off + sy * stride
        rows.append([(data[base + x * step + 2], data[base + x * step + 1], data[base + x * step])
                     for x in range(w)])
    return rows


def cut_out(px, tol=18):
    """Subject mask. The background is the color in the corners, but only where it's connected to the image's edge
    (flood fill), so pale parts inside the subject (a cream face, a white tail tip) aren't cut away with it. Colors
    are compared channel by channel, so a pale tint still counts as different from an off-white background."""
    h, w = len(px), len(px[0])
    corners = [px[0][0], px[0][w - 1], px[h - 1][0], px[h - 1][w - 1]]
    bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))
    near = lambda p: max(abs(p[i] - bg[i]) for i in range(3)) <= tol
    mask = [[True] * w for _ in range(h)]
    stack = [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)]
    while stack:
        y, x = stack.pop()
        if not mask[y][x] or not near(px[y][x]):
            continue
        mask[y][x] = False
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny][nx]:
                stack.append((ny, nx))
    return mask


def subject_cells(px, mask, box, dark_win=0.25):
    """Shrink the subject into board cells inside `box` (left, top, width, height in cells), keeping its shape."""
    h, w = len(px), len(px[0])
    ys = [y for y in range(h) if any(mask[y])]
    xs = [x for x in range(w) if any(mask[y][x] for y in range(h))]
    y0, y1, x0, x1 = min(ys), max(ys) + 1, min(xs), max(xs) + 1
    bl, bt, bw, bh = box
    scale = min(bw / (x1 - x0), bh / (y1 - y0))   # cells per pixel
    cw, ch = round((x1 - x0) * scale), round((y1 - y0) * scale)
    left = bl + (bw - cw) // 2
    top = bt + bh - ch                             # stand on the bottom of the box
    cells = {}
    place = lambda y, x: (top + int((y - y0) * scale), left + int((x - x0) * scale))
    for cy in range(ch):
        for cx in range(cw):
            votes, cov, tot = {}, 0, 0
            for y in range(int(y0 + cy / scale), min(h, int(y0 + (cy + 1) / scale))):
                for x in range(int(x0 + cx / scale), min(w, int(x0 + (cx + 1) / scale))):
                    tot += 1
                    if mask[y][x]:
                        cov += 1
                        p = px[y][x]
                        # Grey pixels stay grey: with every color allowed, light grey fur would match lavender.
                        k = nearest(p, NEUTRAL if max(p) - min(p) < 28 else SUBJECT)
                        votes[k] = votes.get(k, 0) + 1
            if tot and cov / tot >= 0.45:
                # Small dark features (eyes, nose) win a block if they cover a quarter of it, so they survive.
                dark = [k for k in votes if k in DARK and votes[k] >= dark_win * cov]
                cells[(top + cy, left + cx)] = max(dark or votes, key=votes.get)
    # Features too small to win a block (pupils, nostrils, small dark eyes): each small dark spot inside the subject
    # gets one block of its own, at its center, so faces keep their eyes.
    cell_px = 1 / scale
    for comp in dark_spots(px, mask, (y0, y1, x0, x1), cell_px):
        cy = sum(p[0] for p in comp) / len(comp)
        cx = sum(p[1] for p in comp) / len(comp)
        rc = place(cy, cx)
        if rc in cells:
            cells[rc] = "K"
    return cells


def dark_spots(px, mask, box, cell_px):
    """Small, compact dark blobs inside the subject (bigger than a speck, smaller than about 4 blocks)."""
    y0, y1, x0, x1 = box
    dark = lambda p: max(p) < 110 or (p[2] > 120 and p[0] < 90 and p[1] < 140)   # black/brown, or a blue iris
    seen, out = set(), []
    lo, hi = 0.08 * cell_px * cell_px, 4.0 * cell_px * cell_px
    for y in range(y0, y1):
        for x in range(x0, x1):
            if (y, x) in seen or not mask[y][x] or not dark(px[y][x]):
                continue
            comp, stack = [], [(y, x)]
            seen.add((y, x))
            while stack and len(comp) <= hi:
                a, b = stack.pop()
                comp.append((a, b))
                for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (a + da, b + db)
                    if y0 <= q[0] < y1 and x0 <= q[1] < x1 and q not in seen and mask[q[0]][q[1]] \
                            and dark(px[q[0]][q[1]]):
                        seen.add(q)
                        stack.append(q)
            if lo <= len(comp) <= hi:
                hgt = max(p[0] for p in comp) - min(p[0] for p in comp) + 1
                wid = max(p[1] for p in comp) - min(p[1] for p in comp) + 1
                if max(hgt, wid) <= 3 * min(hgt, wid) and len(comp) >= 0.35 * hgt * wid:
                    out.append(comp)
    return out


DARK = ("K", "N", "U", "M", "E")


def simplify(cells, keep=6):
    """At most `keep` colors (plus dark features): rarer colors move to the nearest kept one."""
    count = {}
    for k in cells.values():
        count[k] = count.get(k, 0) + 1
    kept = [k for k, _ in sorted(count.items(), key=lambda kv: -kv[1]) if k not in DARK][:keep]
    kept += [k for k in count if k in DARK]
    return {p: (k if k in kept else nearest(RGB[k], kept)) for p, k in cells.items()}


def tidy(cells):
    """Stray single blocks (a lone color all four neighbours disagree with) take their neighbours' color. Dark
    features are kept: a single dark block is usually an eye."""
    out = dict(cells)
    for (r, c), k in cells.items():
        if k in DARK:
            continue
        nb = [cells.get((r + dr, c + dc)) for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        nb = [n for n in nb if n]
        if len(nb) >= 3 and k not in nb:
            out[(r, c)] = max(sorted(set(nb)), key=nb.count)
    return out


def dark_share(px, mask):
    """Share of the subject's pixels that are near-black: outlined clipart runs 15-30%, flat art under 10%."""
    n = d = 0
    for row, mrow in zip(px, mask):
        for p, m in zip(row, mrow):
            if m:
                n += 1
                d += max(p) < 70
    return d / max(1, n)


def drop_ground(px, mask):
    """Clipart often stands its subject on a patch of grass or a grey shadow: drop green and grey pixels in the
    bottom fifth of the subject, plus anything left below the subject's lowest non-ground part."""
    h, w = len(px), len(px[0])
    ys = [y for y in range(h) if any(mask[y])]
    if not ys:
        return
    top, bot = min(ys), max(ys)
    cut = bot - (bot - top) * 0.2
    green = lambda p: p[1] > p[0] + 25 and p[1] > p[2] + 15
    grey = lambda p: max(p) - min(p) < 18 and 70 < max(p) < 225
    for y in range(int(cut), bot + 1):
        for x in range(w):
            if mask[y][x] and (green(px[y][x]) or grey(px[y][x])):
                mask[y][x] = False


def fill_ratio(mask):
    """How much of the subject's bounding box it fills. Line drawings come out near 0.1 and can't be converted."""
    h, w = len(mask), len(mask[0])
    ys = [y for y in range(h) if any(mask[y])]
    xs = [x for x in range(w) if any(mask[y][x] for y in range(h))]
    box = (max(ys) - min(ys) + 1) * (max(xs) - min(xs) + 1)
    return sum(sum(row) for row in mask) / box


def outline(cells):
    """The game's look: a one-block dark edge outside the subject, only where its edge isn't dark already."""
    out = dict(cells)
    for (r, c), k in cells.items():
        if k in DARK:
            continue
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (r + dr, c + dc)
            if p not in cells and 0 <= p[0] < N and 0 <= p[1] < N:
                out[p] = "K"
    return out


# Light comes from the top left. Each color's lighter and darker tone in the palette (None: none).
# Shadows shift hue the way pixel artists do (orange shades to red, not brown).
SHADE = {
    "O": ("J", "Q"), "Q": ("O", "M"), "J": ("Z", "O"), "R": ("P", "M"), "Y": ("Z", "O"), "Z": ("W", "Y"),
    "W": (None, "X"), "X": ("W", "A"), "T": ("X", "N"), "P": ("W", "S"), "S": ("P", "M"), "N": ("T", "E"),
    "E": ("N", "K"), "A": ("X", "K"), "G": ("L", "D"), "L": ("Z", "G"), "B": ("C", "U"), "C": ("H", "B"),
    "H": ("W", "C"), "I": ("W", "V"), "V": ("I", "U"),
}


def shade(cells, body=None, min_patch=16, hi_patch=40):
    """3D shading, run after the outline: a one-block shadow along the subject's lower-right edge (where the outline is
    below or to the right) and a one-block highlight along its upper-left edge, for big enough patches of one color.
    The outline and dark features stay as they are."""
    size = {}
    seen = set()
    for start, k in cells.items():
        if start in seen or k not in SHADE:
            continue
        patch, stack = [], [start]
        seen.add(start)
        while stack:
            p = stack.pop()
            patch.append(p)
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (p[0] + dr, p[1] + dc)
                if q not in seen and cells.get(q) == k:
                    seen.add(q)
                    stack.append(q)
        for p in patch:
            size[p] = len(patch)
    out = dict(cells)
    # Only the silhouette counts as an edge: outside the subject's body (the outline or beyond), not its eyes.
    body = set(body) if body is not None else {p for p, k in cells.items() if k != "K"}
    edge = lambda q: q not in body
    for (r, c), k in cells.items():
        if k not in SHADE or size.get((r, c), 0) < min_patch:
            continue
        hi, lo = SHADE[k]
        if lo and (edge((r + 1, c)) or edge((r, c + 1))) and not (edge((r - 1, c)) or edge((r, c - 1))):
            out[(r, c)] = lo
        elif hi and size[(r, c)] >= hi_patch and (edge((r - 1, c)) or edge((r, c - 1))) \
                and not (edge((r + 1, c)) or edge((r, c + 1))):
            out[(r, c)] = hi
    return out


def patches(cells):
    """Each connected patch of one color, as lists of positions."""
    seen, out = set(), []
    for start, k in cells.items():
        if start in seen:
            continue
        patch, stack = [], [start]
        seen.add(start)
        while stack:
            p = stack.pop()
            patch.append(p)
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (p[0] + dr, p[1] + dc)
                if q not in seen and cells.get(q) == k:
                    seen.add(q)
                    stack.append(q)
        out.append((k, patch))
    return out


def form_shade(cells, min_patch=50):
    """Break up big single-color areas: the part of each big patch away from the light (lower right) takes the darker
    tone, blended in over a checkered (dithered) band, and a small dithered highlight sits at its upper left. Run
    before the outline and the rim shading."""
    out = dict(cells)
    for k, patch in patches(cells):
        if len(patch) < min_patch or k not in SHADE:
            continue
        hi, lo = SHADE[k]
        r0 = min(p[0] for p in patch); r1 = max(p[0] for p in patch)
        c0 = min(p[1] for p in patch); c1 = max(p[1] for p in patch)
        h, w = max(1, r1 - r0), max(1, c1 - c0)
        for (r, c) in patch:
            u = ((r - r0) / h + (c - c0) / w) / 2      # 0 at the lit corner, 1 at the far one
            # Close tones blend softly: a solid shadow on the far side, a sparse 1-in-4 dither before it.
            sparse = (r % 2 == 0) and ((c + r // 2) % 2 == 0)
            if lo and (u > 0.70 or (u > 0.60 and sparse)):
                out[(r, c)] = lo
            elif hi and (u < 0.16 or (u < 0.24 and sparse)):
                out[(r, c)] = hi
    return out


def ground_shadow(g, cells, horizon=20):
    """The subject's shadow on the ground: one or two blocks out from its lower-right side, in each ground color's
    darker tone."""
    for (r, c) in list(cells):
        for dr, dc in ((1, 0), (1, 1), (0, 1), (1, 2)):
            q = (r + dr, c + dc)
            if q not in cells and 0 <= q[0] < N and 0 <= q[1] < N and q[0] >= horizon:
                lo = SHADE.get(g[q[0]][q[1]], (None, None))[1]
                if lo:
                    g[q[0]][q[1]] = lo


def flowers(g, taken, n=6):
    """Small flowers in the grass, away from the subject: a yellow middle with four petals."""
    import random
    rnd = random.Random(7)
    placed, tries = 0, 0
    near = set()
    for (r, c) in taken:
        for dr in range(-2, 3):
            for dc in range(-2, 3):
                near.add((r + dr, c + dc))
    while placed < n and tries < 400:
        tries += 1
        r, c = rnd.randint(22, N - 3), rnd.randint(1, N - 2)
        spot = [(r, c), (r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
        if any(p in near for p in spot) or any(g[p[0]][p[1]] not in ("L", "G", "D") for p in spot):
            continue
        petal = rnd.choice(["W", "P", "R", "V"])
        for p in spot[1:]:
            g[p[0]][p[1]] = petal
        g[r][c] = "Y"
        for p in spot:
            near.add(p)
        placed += 1


def backdrop(horizon=19):
    """Sky (deep blue at the very top), a rolling lavender hill line, light and dark grass."""
    import math
    g = [["C"] * N for _ in range(N)]
    for r in range(N):
        for c in range(N):
            # Sky: deep blue at the top, blended into the light sky, and paler toward the horizon.
            sparse = (r % 2 == 0) and ((c + r // 2) % 2 == 0)
            if r < 2 or (r < 4 and sparse) or (r == 2 and c % 2 == 0):
                g[r][c] = "B"
            elif r >= horizon - 6 or (r >= horizon - 9 and sparse):
                g[r][c] = "H"
            ridge = horizon - 3 + round(1.6 * math.sin(c / 5.5) + 0.8 * math.sin(c / 2.3 + 1))
            if r >= ridge:
                g[r][c] = "I"
            if r >= horizon:
                g[r][c] = "L" if (r + (c * 3) % 5) % 6 else "G"
            if r >= N - 4:
                g[r][c] = "G" if (c + r) % 4 else "D"
    return g


def place_cloud(g, taken):
    """One big cloud: white with a grey underside, in the open sky part farthest from the subject."""
    shape = ["..WWW.....",
             ".WWWWW.WW.",
             "WWWWWWWWWW",
             "AAAAAAAAAA"]
    best = None
    for top in range(3, 9):
        for left in range(1, N - len(shape[0]) - 1):
            cells = [(top + r, left + c) for r, row in enumerate(shape) for c, ch in enumerate(row) if ch != "."]
            gap = min(abs(r - tr) + abs(c - tc) for (r, c) in cells for (tr, tc) in taken)
            if gap >= 4 and (best is None or gap > best[0]):
                best = (gap, top, left)
    if best:
        _, top, left = best
        for r, row in enumerate(shape):
            for c, ch in enumerate(row):
                if ch != ".":
                    g[top + r][left + c] = ch
        # A sun in the far corner from the cloud, with an orange rim so it reads against the pale sky.
        sc = 6 if left > N // 2 else N - 7
        for r in range(3, 9):
            for c in range(sc - 3, sc + 4):
                d = (r - 5.5) ** 2 + (c - sc) ** 2
                if d <= 6.5:
                    g[r][c] = "Y" if d <= 3.2 else "O"


class Rejected(Exception):
    """A source image that can't make a good board (line art, nothing to cut out)."""


def make_subject(path):
    """The subject from an image: shaded, outlined cells keyed by (row, col), plus facts used to judge the source."""
    px = load(path)
    mask = cut_out(px)
    if not any(any(r) for r in mask):
        raise Rejected("nothing to cut out")
    drop_ground(px, mask)
    fill = fill_ratio(mask)
    if fill < 0.25:
        raise Rejected(f"the subject fills only {fill:.0%} of its box (line art or a thin drawing)")
    # Art drawn with thick black outlines would turn all black at board size if dark pixels won easily (which is
    # what keeps small eyes alive in flat art), so for outlined art a dark color needs half a block to win.
    ink = dark_share(px, mask)
    cells = subject_cells(px, mask, (2, 9, N - 4, N - 12), dark_win=0.5 if ink > 0.12 else 0.25)
    body = tidy(simplify(cells))
    cells = shade(outline(form_shade(body)), body=body)
    colors = {}
    for k in body.values():
        colors[k] = colors.get(k, 0) + 1
    return cells, dict(fill=fill, ink=ink, size=len(body), colors=colors)


def clash(g, cells, info):
    """How much of the backdrop right around the subject is close in color to the subject's main colors (0-1)."""
    main = [k for k, _ in sorted(info["colors"].items(), key=lambda kv: -kv[1])[:3]]
    ring = set()
    for (r, c) in cells:
        for dr in (-2, -1, 0, 1, 2):
            for dc in (-2, -1, 0, 1, 2):
                q = (r + dr, c + dc)
                if q not in cells and 0 <= q[0] < N and 0 <= q[1] < N:
                    ring.add(q)
    close = sum(1 for (r, c) in ring if min(dist(RGB[g[r][c]], RGB[k]) for k in main) < 9000)
    return close / max(1, len(ring))


def compose(cells, info, candidates, seed_base=0):
    """Put the subject on the first candidate (theme, variant) backdrop whose colors don't clash with it (else the
    least clashing). Returns rows, theme index and variant."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import backdrops
    best = None
    for theme, variant in candidates:
        g, h = backdrops.draw(theme, variant, avoid=list(cells), seed_base=seed_base)
        score = clash(g, cells, info)
        if best is None or score < best[0]:
            best = (score, g, h, theme, variant)
        if score < 0.18:
            break
    _, g, h, theme, variant = best
    ground_shadow(g, cells, h)
    for (r, c), k in cells.items():
        g[r][c] = k
    return ["".join(r) for r in g], theme, variant


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--name", default="Imported")
    ap.add_argument("--board", type=int, default=0, help="board number, which picks the backdrop theme and variant")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    try:
        cells, info = make_subject(a.image)
    except Rejected as e:
        sys.exit(f"rejected: {e}")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import backdrops
    rows, theme, variant = compose(cells, info, [backdrops.theme_for(a.board)])
    json.dump({"name": a.name, "rows": rows, "theme": backdrops.THEMES[theme]["name"]}, open(a.out, "w"), indent=1)
    print("\n".join(rows))


if __name__ == "__main__":
    main()
