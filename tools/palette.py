"""The game's 19 colors, and how a board drawn with the old 25-color palette is adapted to them.

The 25-color palette had 7 in-between shades. Raspberry (S) is as easy to tell apart as the standard colors, so it
stays; the other six (Q deep orange, J peach, H pale blue, E dark brown, X stone, and since 2026-11-13 Z pale yellow)
sit too close to a standard color to tell apart in play, so they are gone.

`limit(rows)` then keeps each board to at most 12 colors (MAX_COLORS), the old hand-made boards' level, and merges
away any color with fewer than 5 blocks (MIN_CELLS): such a color can only be a nest smaller than 5.

`adapt(rows)` looks at each board on its own. For every dropped shade it uses, it tries the two closest of the 20
colors and picks the one that costs the picture least: the closer color, unless that color already sits right next
to the shade on this board (merging them would erase an edge, e.g. a shadow melting into a same-colored backdrop),
in which case the other one keeps the edge. Run as a script, it rewrites the game's board files in place.
"""
import itertools
import json
import os
import sys

PALETTE = {
    "R": 0xE53935, "O": 0xFB8C00, "Y": 0xFDD835, "G": 0x43A047, "B": 0x1E88E5, "V": 0x8E24AA,
    "P": 0xF48FB1, "N": 0x795548, "W": 0xF5F5F5, "K": 0x263238, "T": 0xD2B48C, "A": 0x9E9E9E,
    "L": 0x9CCC65, "D": 0x1B5E20, "M": 0x8E1B1B, "C": 0x81D4FA, "U": 0x283593, "I": 0xB39DDB,
    "S": 0xD81B60,
}
DROPPED = {"Q": 0xE65100, "J": 0xFFB74D, "H": 0xB3E5FC, "E": 0x4E342E, "X": 0xD7CCC8, "Z": 0xFFF59D}
# The plain answer for each dropped shade, used by the game for any old board that was not adapted.
FALLBACK = {"Q": "O", "J": "O", "H": "C", "E": "N", "X": "W", "Z": "Y"}


def lab(hexv):
    def f(u):
        u /= 255
        return ((u + 0.055) / 1.055) ** 2.4 if u > 0.04045 else u / 12.92
    r, g, b = (f((hexv >> s) & 255) for s in (16, 8, 0))
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.9505
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.089
    h = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    return 116 * h(y) - 16, 500 * (h(x) - h(y)), 200 * (h(y) - h(z))


def delta(a, b):
    return sum((p - q) ** 2 for p, q in zip(lab(a), lab(b))) ** 0.5


# The two closest of the game's colors to each dropped shade, closest first, with how far each is.
CANDIDATES = {s: sorted((delta(v, PALETTE[k]), k) for k in PALETTE)[:2] for s, v in DROPPED.items()}
# Pale yellow reads as a yellow (or, beside yellow, a highlight), never as the light green Lab puts nearer to it.
CANDIDATES["Z"] = sorted((delta(DROPPED["Z"], PALETTE[k]), k) for k in "YW")


def adapt(rows, report=None):
    """The board redrawn in the game's colors. `report`, if given, collects {shade: chosen color}."""
    grid = [list(r) for r in rows]
    h, w = len(grid), max(len(r) for r in grid)
    used = {ch for r in grid for ch in r}
    choice = {}
    for s in DROPPED:
        if s not in used:
            continue
        cells = [(r, c) for r in range(h) for c in range(len(grid[r])) if grid[r][c] == s]
        touch = {}
        for r, c in cells:
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                rr, cc = r + dr, c + dc
                if 0 <= rr < h and 0 <= cc < len(grid[rr]):
                    touch[grid[rr][cc]] = touch.get(grid[rr][cc], 0) + 1
        border = sum(v for k, v in touch.items() if k != s) or 1
        # Cost: color distance, plus a penalty for the share of the shade's border that would vanish.
        cost = lambda d_k: d_k[0] + 40 * touch.get(d_k[1], 0) / border
        choice[s] = min(CANDIDATES[s], key=cost)[1]
    out = ["".join(choice.get(ch, ch) for ch in r) for r in grid]
    if report is not None:
        report.update(choice)
    return out


MAX_COLORS = 12
MIN_CELLS = 5


def _touching(rows, ch):
    """How many cell edges `ch` shares with each other color, and its whole border."""
    h = len(rows)
    touch = {}
    for r in range(h):
        for c, x in enumerate(rows[r]):
            if x != ch:
                continue
            for rr, cc in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
                if 0 <= rr < h and 0 <= cc < len(rows[rr]) and rows[rr][cc] not in (ch, "."):
                    touch[rows[rr][cc]] = touch.get(rows[rr][cc], 0) + 1
    return touch, sum(touch.values()) or 1


def limit(rows, max_colors=MAX_COLORS, min_cells=MIN_CELLS):
    """The board with at most `max_colors` colors, none of them under `min_cells` blocks: while it breaks either
    rule, its rarest color becomes the closest of the others (small details and shading tones go first; big areas
    and the outline stay). A tiny color avoids the color it sits on where a close one is available, so a pupil or a
    button doesn't simply vanish into its surroundings. Any dropped shade is adapted first."""
    rows = adapt(rows)
    while True:
        count = {}
        for ch in "".join(rows):
            if ch != ".":
                count[ch] = count.get(ch, 0) + 1
        rare = min(count, key=lambda k: (count[k], k)) if count else None
        if rare is None or len(count) == 1 or (len(count) <= max_colors and count[rare] >= min_cells):
            return rows
        touch, border = _touching(rows, rare)
        to = min((k for k in count if k != rare),
                 key=lambda k: delta(PALETTE[rare], PALETTE[k]) + 40 * touch.get(k, 0) / border)
        rows = [r.replace(rare, to) for r in rows]


def adapt_file(path):
    d = json.load(open(path))
    stats = {"boards": 0, "changed": 0, "before": 0, "after": 0, "choices": {}}

    changed_ids = set()

    def one(rows):
        rep = {}
        new = limit(adapt(rows, rep))
        stats["boards"] += 1
        stats["before"] += len(set("".join(rows)) - {"."})
        stats["after"] += len(set("".join(new)) - {"."})
        for s, k in rep.items():
            stats["choices"][f"{s}>{k}"] = stats["choices"].get(f"{s}>{k}", 0) + 1
        if new != rows:
            stats["changed"] += 1
        return new

    def walk(x):
        if isinstance(x, dict):
            if isinstance(x.get("rows"), list) and x["rows"] and isinstance(x["rows"][0], str):
                new = one(x["rows"])
                if new != x["rows"]:
                    changed_ids.add(x.get("id"))
                    x["rows"] = new
            # Coin Mining pictures: the same picture with a different background per round.
            if isinstance(x.get("variants"), list):
                x["variants"] = [one(v) for v in x["variants"]]
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)

    walk(d)
    # Pre-built boards number the colors of the picture they were built from, so a recolored picture can't use one.
    if isinstance(d, dict) and isinstance(d.get("baked"), dict):
        drop = [k for k in d["baked"] if k.split("|")[0] in changed_ids]
        for k in drop:
            del d["baked"][k]
        stats["baked dropped"] = len(drop)
    return d, stats


if __name__ == "__main__":
    for path in sys.argv[1:]:
        d, st = adapt_file(path)
        raw = open(path).read()
        compact = "\n" not in raw.strip()
        with open(path, "w") as f:
            json.dump(d, f, separators=(",", ":") if compact else None, indent=None if compact else 1)
        n = max(1, st["boards"])
        print(f"{os.path.basename(path)}: {st['boards']} boards, {st['changed']} changed, colors per board "
              f"{st['before'] / n:.1f} -> {st['after'] / n:.1f}; {dict(sorted(st['choices'].items()))}"
              + (f"; pre-built boards dropped: {st['baked dropped']}" if "baked dropped" in st else ""))
