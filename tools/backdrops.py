"""Backdrops for imported boards: 50+ themes built from shared parts, so no two boards get the same background.

A theme is a sky, a middle ground, a ground and some props (see THEMES). Every board draws its theme with its own
variant number, which moves the horizon, reshapes hills and skylines, and re-scatters stars, clouds and props, so
parts repeat but whole backgrounds don't. `theme_for(n)` spreads the themes so the same one never comes back within
about 50 boards.

    python3 -I tools/backdrops.py --sheet out.png     # every theme, one tile each, for review

All drawing is in palette letters on a 40x40 grid; rows go top to bottom.
"""
import math
import random

N = 40


def grid(fill="C"):
    return [[fill] * N for _ in range(N)]


def put(g, r, c, ch):
    if 0 <= r < N and 0 <= c < N:
        g[r][c] = ch


def sparse(r, c):
    """A 1-in-4 dither pattern for soft blends."""
    return r % 2 == 0 and (c + r // 2) % 2 == 0


def bands(g, top, bottom, colors):
    """Vertical gradient from `top` to `bottom` through `colors`, dithered at each step."""
    n = len(colors)
    for r in range(top, bottom):
        f = (r - top) / max(1, bottom - top) * n
        k = min(n - 1, int(f))
        edge = f - k > 0.7 and k + 1 < n
        for c in range(N):
            g[r][c] = colors[k + 1] if edge and sparse(r, c) else colors[k]


# ---------------------------------------------------------------- skies

def sky_day(g, R, h):
    bands(g, 0, h, ["B", "C", "C", "H"])


def sky_sunset(g, R, h):
    bands(g, 0, h, ["U", "V", "S", "Q", "O", "J"])


def sky_dawn(g, R, h):
    bands(g, 0, h, ["I", "P", "P", "J", "Z"])


def sky_golden(g, R, h):
    bands(g, 0, h, ["J", "Y", "Z", "Z"])


def sky_night(g, R, h):
    bands(g, 0, h, ["K", "U", "U"])
    stars(g, R, 0, h - 2, 14)


def sky_space(g, R, h):
    for r in range(h):
        for c in range(N):
            g[r][c] = "K"
    stars(g, R, 0, h, 26)


def sky_overcast(g, R, h):
    bands(g, 0, h, ["A", "X", "X", "W"])


def sky_storm(g, R, h):
    bands(g, 0, h, ["K", "A", "A", "X"])
    for _ in range(R.randint(4, 7)):            # rain streaks
        c, r = R.randint(0, N - 1), R.randint(0, h - 4)
        for i in range(3):
            put(g, r + i, c - i // 2, "H")


def sky_aurora(g, R, h):
    bands(g, 0, h, ["K", "K", "U"])
    ph = R.random() * 6
    for c in range(N):
        y = int(4 + 3 * math.sin(c / 6 + ph))
        for i, ch in enumerate(("L", "G", "C")):
            put(g, y + i * 2, c, ch)
            if sparse(y + i * 2 + 1, c):
                put(g, y + i * 2 + 1, c, ch)
    stars(g, R, 0, h - 2, 8)


def sky_underwater(g, R, h):
    bands(g, 0, N, ["C", "B", "B", "U"])
    for _ in range(3):                          # light rays
        c = R.randint(2, N - 8)
        for r in range(0, 14):
            if sparse(r, c + r // 2):
                put(g, r, c + r // 2, "H")
    for _ in range(R.randint(3, 5)):            # bubbles
        c, r = R.randint(1, N - 2), R.randint(2, 20)
        for i in range(3):
            put(g, r - i * 3, c + (i % 2), "W")


def sky_cave(g, R, h):
    bands(g, 0, h, ["K", "E", "E", "N"])
    for _ in range(R.randint(5, 8)):            # stalactites
        c, n = R.randint(0, N - 2), R.randint(2, 6)
        for i in range(n):
            put(g, i, c, "N")
            if i < n - 2:
                put(g, i, c + 1, "E")


def wall(pattern):
    def draw(g, R, h):
        a, b = pattern["colors"]
        k = pattern["kind"]
        for r in range(h):
            for c in range(N):
                if k == "stripes":
                    ch = a if (c // 3) % 2 == 0 else b
                elif k == "dots":
                    ch = b if r % 4 == 1 and (c + (r // 4) * 2) % 4 == 1 else a
                elif k == "plaid":
                    ch = b if r % 6 in (0, 1) or c % 6 in (0, 1) else a
                elif k == "brick":
                    ch = b if r % 3 == 2 or (c + (r // 3 % 2) * 3) % 6 == 0 else a
                else:  # panels
                    ch = b if c % 5 == 0 else a
                g[r][c] = ch
        for c in range(N):                      # skirting board
            put(g, h - 1, c, "N")
    return draw


def stars(g, R, top, bottom, n):
    for _ in range(n):
        r, c = R.randint(top, max(top, bottom - 1)), R.randint(0, N - 1)
        put(g, r, c, R.choice(["W", "Z", "W", "H"]))


# ---------------------------------------------------------------- sky props

def sun(g, R, h, avoid):
    side = R.choice([5, N - 6])
    r0 = R.randint(3, max(3, min(7, h - 6)))
    for r in range(r0 - 3, r0 + 4):
        for c in range(side - 3, side + 4):
            d = (r - r0) ** 2 + (c - side) ** 2
            if d <= 10:
                put(g, r, c, "Y" if d <= 4 else ("J" if d <= 7 else "O"))
                avoid.append((r, c))


def moon(g, R, h, avoid):
    side = R.choice([5, N - 6])
    r0 = R.randint(3, 6)
    for r in range(r0 - 3, r0 + 4):
        for c in range(side - 3, side + 4):
            if (r - r0) ** 2 + (c - side) ** 2 <= 9:
                put(g, r, c, "Z" if (r - r0 + 1) ** 2 + (c - side - 2) ** 2 > 6 else g[r][c])
                avoid.append((r, c))


def planet(g, R, h, avoid):
    side, r0 = R.choice([6, N - 7]), R.randint(5, 9)
    col, ring = R.choice([("Q", "J"), ("I", "W"), ("S", "P"), ("L", "Z")])
    for r in range(r0 - 4, r0 + 5):
        for c in range(side - 6, side + 7):
            d = (r - r0) ** 2 + (c - side) ** 2
            if d <= 12:
                put(g, r, c, col if (r - r0) + (c - side) < 2 else ("M" if col in "QS" else "V"))
                avoid.append((r, c))
            elif abs((r - r0) - (c - side) * 0.25) < 0.6 and abs(c - side) <= 6:
                put(g, r, c, ring)


CLOUD_SHAPES = [
    ["..WWW....", ".WWWWW.W.", "WWWWWWWWW", "XXXXXXXXX"],
    [".WW......", "WWWWWWW..", "WWWWWWWWW", ".XXXXXXX."],
    ["....WW...", "..WWWWWW.", "WWWWWWWWW", "XXXXXXXX."],
]


def clouds(g, R, h, avoid, n=2):
    placed = []
    for _ in range(n):
        shape = R.choice(CLOUD_SHAPES)
        for _ in range(60):
            top, left = R.randint(2, max(2, h - 9)), R.randint(0, N - len(shape[0]))
            cells = [(top + r, left + c) for r, row in enumerate(shape) for c, ch in enumerate(row) if ch != "."]
            if any(abs(r - ar) + abs(c - ac) < 4 for (r, c) in cells for (ar, ac) in avoid + placed):
                continue
            for r, row in enumerate(shape):
                for c, ch in enumerate(row):
                    if ch != ".":
                        put(g, top + r, left + c, ch)
            placed += cells
            break


def birds(g, R, h, avoid):
    for _ in range(R.randint(2, 4)):
        r, c = R.randint(3, max(3, h - 5)), R.randint(2, N - 4)
        if any(abs(r - ar) + abs(c - ac) < 4 for ar, ac in avoid):
            continue
        put(g, r, c, "K"); put(g, r - 1, c - 1, "K"); put(g, r - 1, c + 1, "K")
        avoid.append((r, c))


# ---------------------------------------------------------------- middle grounds (a band above the horizon)

def mid_hills(colors):
    def draw(g, R, h):
        ph = R.random() * 6
        for c in range(N):
            top = h - 4 + round(2 * math.sin(c / (4 + R.random() * 0.4) + ph) + math.sin(c / 2.1 + ph))
            for r in range(top, h):
                put(g, r, c, colors[0] if r - top < 2 else colors[1])
    return draw


def mid_mountains(g, R, h):
    peaks = [R.randint(0, N - 1) for _ in range(3)]
    for c in range(N):
        top = min(h - 2, min(h - 12 + abs(c - p) for p in peaks) + R.randint(0, 1))
        for r in range(top, h):
            put(g, r, c, "W" if r - top < 2 and top < h - 7 else ("A" if (c + r) % 5 else "X"))


def mid_pines(g, R, h):
    for x in range(-2, N, 4):
        x += R.randint(0, 1)
        t = R.randint(6, 10)
        for i in range(t):
            for dc in range(-(i // 2), i // 2 + 1):
                put(g, h - t + i, x + dc, "D" if dc >= 0 else "G")
        put(g, h - 1, x, "E")


def mid_trees(g, R, h):
    for x in range(1, N, 6):
        x += R.randint(-1, 1)
        rad = R.randint(2, 3)
        cy = h - rad - 2
        for r in range(cy - rad, cy + rad + 1):
            for c in range(x - rad, x + rad + 1):
                if (r - cy) ** 2 + (c - x) ** 2 <= rad * rad + 1:
                    put(g, r, c, "L" if (r - cy) + (c - x) < 0 else "G")
        put(g, h - 1, x, "N"); put(g, h - 2, x, "N")


def mid_city(g, R, h):
    c = 0
    while c < N:
        w, t = R.randint(3, 6), R.randint(5, 13)
        col = R.choice(["U", "A", "V", "E"])
        for r in range(h - t, h):
            for x in range(c, min(N, c + w)):
                win = (r - (h - t)) % 2 == 1 and (x - c) % 2 == 1 and x - c < w - 1
                put(g, r, x, ("Z" if R.random() < 0.6 else "Y") if win else col)
        c += w + R.randint(0, 1)


def mid_palms(g, R, h):
    for x in R.sample(range(3, N - 3), 3):
        t = R.randint(8, 12)
        for i in range(t):
            put(g, h - i, x + (i // 5), "N" if i % 2 else "E")
        top = (h - t, x + t // 5)
        for dr, dc in ((-1, -3), (-1, -2), (0, -4), (-1, 2), (-1, 3), (0, 4), (-2, -1), (-2, 1), (-2, 0)):
            put(g, top[0] + dr, top[1] + dc, "G")
            put(g, top[0] + dr + 1, top[1] + dc + (1 if dc > 0 else -1), "D")


def mid_cacti(g, R, h):
    for x in R.sample(range(2, N - 2), 3):
        t = R.randint(5, 8)
        for i in range(t):
            put(g, h - i - 1, x, "G")
        arm = h - t + 2
        put(g, arm, x - 1, "G"); put(g, arm - 1, x - 2, "G"); put(g, arm - 2, x - 2, "G")
        put(g, arm + 1, x + 1, "D"); put(g, arm, x + 2, "D")


def mid_sea(g, R, h):
    for r in range(h - 5, h):
        for c in range(N):
            g[r][c] = "B" if r < h - 2 else ("C" if (c + r) % 5 else "W")


def mid_castle(g, R, h):
    x0 = R.randint(4, N - 18)
    for c in range(x0, x0 + 14):
        top = h - 8 - (3 if c in (x0, x0 + 1, x0 + 12, x0 + 13) else 0) - (1 if c % 2 == 0 else 0)
        for r in range(top, h):
            put(g, r, c, "X" if (r + c) % 4 else "A")
    for r in range(h - 4, h):
        put(g, r, x0 + 6, "E"); put(g, r, x0 + 7, "E")
    mid_hills(("L", "G"))(g, R, h)


def mid_barn(g, R, h):
    mid_hills(("L", "G"))(g, R, h)
    x0 = R.randint(2, N - 12)
    for r in range(h - 7, h):
        for c in range(x0, x0 + 9):
            roof = r < h - 5
            put(g, r, c, "M" if roof else ("R" if (c - x0) % 4 else "W"))
    for c in range(x0 - 1, x0 + 10):
        put(g, h - 8, c, "E")


def mid_hedge(g, R, h):
    for c in range(N):
        top = h - 3 - (1 if (c + R.randint(0, 1)) % 3 == 0 else 0)
        for r in range(top, h):
            put(g, r, c, "D" if (r + c) % 3 else "G")


def mid_dunes(g, R, h):
    ph = R.random() * 6
    for c in range(N):
        top = h - 3 + round(2 * math.sin(c / 5 + ph))
        for r in range(top, h):
            put(g, r, c, "J" if r - top < 1 else "T")


def mid_ice(g, R, h):
    for x in R.sample(range(2, N - 2), 4):
        t = R.randint(3, 7)
        for i in range(t):
            for dc in range(-(t - i) // 2, (t - i) // 2 + 1):
                put(g, h - 1 - i, x + dc, "W" if dc <= 0 else "H")


def mid_none(g, R, h):
    pass


def mid_shelf(g, R, h):
    """Indoors: a shelf with jars and a picture frame on the wall."""
    y = h - 9
    for c in range(3, N - 3):
        put(g, y, c, "N")
    for x in R.sample(range(4, N - 6), 4):
        col = R.choice(["R", "B", "Y", "G", "P"])
        for r in range(y - 3, y):
            put(g, r, x, col); put(g, r, x + 1, col)
        put(g, y - 4, x, "X"); put(g, y - 4, x + 1, "X")


def mid_window(g, R, h):
    x0 = R.randint(3, N - 14)
    for r in range(3, 13):
        for c in range(x0, x0 + 11):
            frame = r in (3, 12) or c in (x0, x0 + 10) or c == x0 + 5 or r == 8
            put(g, r, c, "W" if frame else ("H" if r < 8 else "C"))


def mid_reef(g, R, h):
    for x in R.sample(range(1, N - 1), 6):
        t = R.randint(4, 9)
        col = R.choice(["S", "Q", "V", "P"])
        for i in range(t):
            put(g, h - 1 - i, x + (1 if i % 4 == 2 else 0), col)
            if i == t - 2:
                put(g, h - 1 - i, x - 1, col); put(g, h - 1 - i, x + 1, col)


def mid_crystals(g, R, h):
    for x in R.sample(range(2, N - 2), 6):
        t, col = R.randint(3, 7), R.choice([("I", "V"), ("H", "C"), ("P", "S")])
        for i in range(t):
            for dc in range(-(t - i) // 3, (t - i) // 3 + 1):
                put(g, h - 1 - i, x + dc, col[0] if dc <= 0 else col[1])


def mid_craters(g, R, h):
    for c in range(N):
        put(g, h - 1, c, "A")


# ---------------------------------------------------------------- grounds

def ground(colors, kind="tufts"):
    def draw(g, R, h):
        a, b = colors[0], colors[1]
        for r in range(h, N):
            for c in range(N):
                if kind == "tufts":
                    ch = b if (r * 7 + c * 3 + (c // 5)) % 9 == 0 else a
                elif kind == "rows":
                    ch = b if (r - h) % 3 == 0 else a
                elif kind == "planks":
                    ch = b if c % 7 == 0 or (r - h) % 4 == 3 and (c + r) % 7 == 3 else a
                elif kind == "tiles":
                    ch = a if ((r - h) // 3 + c // 3) % 2 == 0 else b
                elif kind == "ripples":
                    ch = b if (r + round(math.sin(c / 3) * 1.5)) % 4 == 0 else a
                elif kind == "cobbles":
                    ch = b if (r - h) % 3 == 2 or (c + ((r - h) // 3) * 2) % 4 == 0 else a
                else:
                    ch = a
                g[r][c] = ch
        if len(colors) > 2:                    # darker foreground strip
            for r in range(N - 3, N):
                for c in range(N):
                    g[r][c] = colors[2] if (c + r) % 4 else b
    return draw


def ground_beach(g, R, h):
    for r in range(h, N):
        for c in range(N):
            if r < h + 4:
                g[r][c] = "B" if r < h + 2 else ("W" if (c + r) % 4 == 0 else "C")
            else:
                g[r][c] = "J" if (r * 5 + c * 3) % 11 == 0 else "T"


def ground_pond(g, R, h):
    ground(("L", "G", "D"))(g, R, h)
    cx = R.choice([8, N - 9])
    for r in range(h + 3, N - 4):
        for c in range(N):
            if ((r - (h + 9)) / 5) ** 2 + ((c - cx) / 9) ** 2 <= 1:
                g[r][c] = "C" if (r + c) % 6 else "H"
    for _ in range(3):                          # lily pads
        r, c = R.randint(h + 6, h + 11), cx + R.randint(-5, 5)
        put(g, r, c, "G"); put(g, r, c + 1, "G")


def ground_river(g, R, h):
    ground(("L", "G", "D"))(g, R, h)
    for r in range(h, N):
        cx = 20 + round(8 * math.sin(r / 5 + R.random()))
        for c in range(cx - 3 - (r - h) // 4, cx + 3 + (r - h) // 4):
            put(g, r, c, "B" if (r + c) % 5 else "H")


def ground_road(g, R, h):
    for r in range(h, N):
        for c in range(N):
            if r < h + 2:
                g[r][c] = "X"
            elif r < N - 5:
                g[r][c] = "Y" if r == (h + N - 5) // 2 and c % 6 < 3 else "A"
            else:
                g[r][c] = "X" if (c // 4 + r) % 2 else "W"


# ---------------------------------------------------------------- ground props

def flowers(g, R, h, avoid, n=5, petals=("W", "P", "R", "V", "Z")):
    _scatter(g, R, h, avoid, n, lambda r, c: _flower(g, r, c, R.choice(petals)))


def _flower(g, r, c, p):
    for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        put(g, r + dr, c + dc, p)
    put(g, r, c, "Y")


def mushrooms(g, R, h, avoid, n=3):
    def m(r, c):
        for dc in (-1, 0, 1):
            put(g, r - 1, c + dc, "R")
        put(g, r - 1, c, "W"); put(g, r, c, "W")
    _scatter(g, R, h, avoid, n, m)


def rocks(g, R, h, avoid, n=3):
    def m(r, c):
        put(g, r, c, "A"); put(g, r, c + 1, "X"); put(g, r - 1, c, "X")
    _scatter(g, R, h, avoid, n, m)


def shells(g, R, h, avoid, n=4):
    def m(r, c):
        put(g, r, c, R.choice(["P", "J", "W"])); put(g, r, c + 1, R.choice(["S", "Q", "X"]))
    _scatter(g, R, h, avoid, n, m)


def pumpkins(g, R, h, avoid, n=3):
    def m(r, c):
        for dc in (-1, 0, 1):
            put(g, r, c + dc, "O"); put(g, r - 1, c + dc, "Q" if dc else "O")
        put(g, r - 2, c, "G")
    _scatter(g, R, h, avoid, n, m)


def snowmen(g, R, h, avoid, n=1):
    def m(r, c):
        for dr, w in ((0, 2), (-3, 1)):
            for rr in range(r + dr - w, r + dr + 1):
                for cc in range(c - w, c + w + 1):
                    put(g, rr, cc, "W")
        put(g, r - 4, c, "K"); put(g, r - 3, c + 1, "O")
    _scatter(g, R, h, avoid, n, m, margin=4)


def leaves(g, R, h, avoid, n=10):
    def m(r, c):
        put(g, r, c, R.choice(["Q", "O", "M", "Y"]))
    _scatter(g, R, h, avoid, n, m, margin=1)


def bushes(g, R, h, avoid, n=2):
    def m(r, c):
        for dr in (-1, 0):
            for dc in (-2, -1, 0, 1, 2):
                if not (dr == -1 and abs(dc) == 2):
                    put(g, r + dr, c + dc, "G" if dr == -1 else "D")
        put(g, r - 1, c - 1, R.choice(["R", "P", "Z"]))
    _scatter(g, R, h, avoid, n, m, margin=4)


def seaweed(g, R, h, avoid, n=4):
    def m(r, c):
        for i in range(5):
            put(g, r - i, c + (i % 2), "G" if i % 2 else "D")
    _scatter(g, R, h, avoid, n, m, margin=3)


def lanterns(g, R, h, avoid, n=3):
    def m(r, c):
        put(g, r - 2, c, "E"); put(g, r - 1, c, "Y"); put(g, r, c, "Q")
    _scatter(g, R, h, avoid, n, m, margin=2)


def butterflies(g, R, h, avoid, n=2):
    for _ in range(n):
        r, c = R.randint(h - 6, h + 6), R.randint(2, N - 3)
        if any(abs(r - ar) + abs(c - ac) < 4 for ar, ac in avoid):
            continue
        col = R.choice(["P", "Z", "I", "J"])
        put(g, r, c - 1, col); put(g, r, c + 1, col); put(g, r, c, "K")


def rug(g, R, h, avoid, n=1):
    r0 = N - 5
    col = R.choice(["S", "R", "V", "B"])
    for r in range(r0, r0 + 3):
        for c in range(4, N - 4):
            g[r][c] = col if (r + c) % 4 else "Z"


def _scatter(g, R, h, avoid, n, draw, margin=3):
    placed = 0
    for _ in range(80):
        if placed >= n:
            break
        r, c = R.randint(h + 2, N - 2), R.randint(2, N - 3)
        if any(abs(r - ar) + abs(c - ac) < margin for ar, ac in avoid):
            continue
        draw(r, c)
        avoid.append((r, c))
        placed += 1


# ---------------------------------------------------------------- themes

GRASS = ground(("L", "G", "D"))
T = lambda name, sky, mid, gnd, props, sky_props=(), h=(19, 23): dict(
    name=name, sky=sky, mid=mid, ground=gnd, props=props, sky_props=sky_props, h=h)

THEMES = [
    T("Spring meadow", sky_day, mid_hills(("I", "V")), GRASS, [flowers, butterflies], [sun, clouds]),
    T("Summer hills", sky_day, mid_hills(("L", "G")), GRASS, [flowers, bushes], [sun, clouds, birds]),
    T("Sunset meadow", sky_sunset, mid_hills(("V", "U")), GRASS, [flowers], [sun]),
    T("Dawn fields", sky_dawn, mid_hills(("P", "I")), ground(("L", "G", "D"), "rows"), [flowers], [sun]),
    T("Golden wheat", sky_golden, mid_hills(("J", "O")), ground(("Y", "J", "O"), "rows"), [], [sun, birds]),
    T("Starry hilltop", sky_night, mid_hills(("U", "K")), ground(("D", "G", "K")), [lanterns], [moon]),
    T("Moonlit pond", sky_night, mid_trees, ground_pond, [rocks], [moon]),
    T("Pine forest", sky_day, mid_pines, ground(("G", "D", "E")), [mushrooms], [clouds]),
    T("Misty pines", sky_overcast, mid_pines, ground(("G", "D", "E")), [rocks, mushrooms], [birds]),
    T("Snowy pines", sky_overcast, mid_pines, ground(("W", "X", "H")), [snowmen], [clouds]),
    T("Winter night", sky_night, mid_mountains, ground(("W", "H", "X")), [snowmen], [moon]),
    T("Ice field", sky_day, mid_ice, ground(("W", "H", "X")), [rocks], [sun, clouds]),
    T("Mountain pass", sky_day, mid_mountains, ground(("A", "X", "K"), "cobbles"), [rocks], [clouds, birds]),
    T("Alpine meadow", sky_day, mid_mountains, GRASS, [flowers, rocks], [sun]),
    T("Mountain sunset", sky_sunset, mid_mountains, ground(("G", "D", "K")), [rocks], [sun, birds]),
    T("Desert dunes", sky_golden, mid_dunes, ground(("T", "J", "N"), "ripples"), [rocks], [sun]),
    T("Cactus canyon", sky_day, mid_cacti, ground(("J", "T", "Q"), "ripples"), [rocks], [sun, birds]),
    T("Desert night", sky_night, mid_cacti, ground(("T", "N", "E"), "ripples"), [], [moon]),
    T("Tropical beach", sky_day, mid_palms, ground_beach, [shells], [sun, clouds]),
    T("Beach sunset", sky_sunset, mid_sea, ground_beach, [shells], [sun, birds]),
    T("Seaside cliffs", sky_day, mid_sea, ground(("A", "X", "G"), "cobbles"), [rocks], [clouds, birds]),
    T("Coral reef", sky_underwater, mid_reef, ground(("T", "J", "Q"), "ripples"), [shells, seaweed], []),
    T("Kelp forest", sky_underwater, mid_none, ground(("T", "J", "N"), "ripples"), [seaweed, rocks], []),
    T("Deep sea", sky_underwater, mid_reef, ground(("U", "B", "K"), "ripples"), [seaweed], []),
    T("Autumn woods", sky_day, mid_trees, ground(("Q", "O", "N")), [leaves, pumpkins], [clouds]),
    T("Harvest farm", sky_golden, mid_barn, ground(("N", "E", "G"), "rows"), [pumpkins], [sun, birds]),
    T("Red barn", sky_day, mid_barn, GRASS, [flowers, bushes], [clouds]),
    T("Orchard", sky_day, mid_trees, GRASS, [flowers], [sun, birds]),
    T("Castle hill", sky_day, mid_castle, GRASS, [flowers, rocks], [clouds, birds]),
    T("Castle at dusk", sky_sunset, mid_castle, ground(("G", "D", "K")), [lanterns], [moon]),
    T("City day", sky_day, mid_city, ground_road, [], [clouds, birds]),
    T("City night", sky_night, mid_city, ground_road, [lanterns], [moon]),
    T("City dawn", sky_dawn, mid_city, ground(("X", "A", "W"), "cobbles"), [], [sun]),
    T("Riverbank", sky_day, mid_trees, ground_river, [rocks, flowers], [clouds]),
    T("Garden pond", sky_day, mid_hedge, ground_pond, [flowers], [sun]),
    T("Rose garden", sky_day, mid_hedge, ground(("G", "L", "D")), [flowers, bushes], [butterflies], ),
    T("Rainy day", sky_storm, mid_trees, ground(("G", "D", "C")), [rocks], []),
    T("Stormy coast", sky_storm, mid_sea, ground(("A", "X", "K"), "cobbles"), [rocks], []),
    T("Northern lights", sky_aurora, mid_pines, ground(("W", "H", "X")), [], []),
    T("Aurora lake", sky_aurora, mid_mountains, ground_pond, [rocks], []),
    T("Outer space", sky_space, mid_craters, ground(("A", "X", "K"), "cobbles"), [rocks], [planet]),
    T("Moon base", sky_space, mid_craters, ground(("X", "A", "W"), "tiles"), [rocks], [planet]),
    T("Cave", sky_cave, mid_none, ground(("E", "N", "K"), "cobbles"), [mushrooms, rocks], [], (24, 27)),
    T("Crystal cave", sky_cave, mid_crystals, ground(("N", "E", "K"), "cobbles"), [lanterns], [], (24, 27)),
    T("Cozy kitchen", wall(dict(kind="plaid", colors=("W", "H"))), mid_shelf, ground(("T", "N"), "planks"), [], [], (26, 29)),
    T("Living room", wall(dict(kind="stripes", colors=("P", "W"))), mid_window, ground(("N", "E"), "planks"), [rug], [], (26, 29)),
    T("Nursery", wall(dict(kind="dots", colors=("H", "Z"))), mid_window, ground(("T", "X"), "planks"), [rug], [], (26, 29)),
    T("Brick cellar", wall(dict(kind="brick", colors=("M", "X"))), mid_shelf, ground(("A", "X"), "tiles"), [], [], (26, 29)),
    T("Cabin", wall(dict(kind="panels", colors=("N", "E"))), mid_window, ground(("T", "N"), "planks"), [rug], [], (26, 29)),
    T("Bakery", wall(dict(kind="dots", colors=("J", "W"))), mid_shelf, ground(("W", "X"), "tiles"), [], [], (26, 29)),
    T("Lavender fields", sky_dawn, mid_hills(("I", "V")), ground(("V", "I", "D"), "rows"), [butterflies], [sun]),
    T("Sunflower farm", sky_day, mid_hills(("L", "G")), ground(("G", "D", "E")), [flowers], [sun, clouds]),
    T("Tulip fields", sky_day, mid_barn, ground(("S", "P", "G"), "rows"), [], [clouds]),
    T("Overcast moor", sky_overcast, mid_hills(("X", "A")), ground(("I", "V", "D")), [rocks], [birds]),
    T("Bamboo grove", sky_golden, mid_pines, ground(("L", "G", "D")), [rocks], [birds]),
    T("Waterfall", sky_day, mid_mountains, ground_river, [rocks], [clouds]),
    T("Lantern festival", sky_night, mid_city, ground(("X", "A", "K"), "cobbles"), [lanterns], [moon]),
]
THEMES = [t for t in THEMES if t]

# Which kind of place each theme is, so a pack only gets themes that make sense for it.
_GROUPS = {
    "water": ("Coral reef", "Kelp forest", "Deep sea"),
    "space": ("Outer space", "Moon base"),
    "indoor": ("Cozy kitchen", "Living room", "Nursery", "Brick cellar", "Cabin", "Bakery"),
    "cave": ("Cave", "Crystal cave"),
    "city": ("City day", "City night", "City dawn", "Lantern festival"),
}
for t in THEMES:
    t["group"] = next((g for g, names in _GROUPS.items() if t["name"] in names), "land")
    # Dark skies and rooms: a dark subject would vanish against them.
    t["dark"] = t["sky"] in (sky_night, sky_space, sky_cave, sky_storm, sky_aurora)


def pick_themes(groups, used, recent, n=6, dark_subject=False):
    """Up to n candidate themes for the next board: from the allowed groups, least used first, skipping the ones
    used on the last few boards. Each comes with its next unused variant, so no background is ever repeated."""
    ok = [i for i, t in enumerate(THEMES) if t["group"] in groups and not (dark_subject and t["dark"])]
    pool = [i for i in ok if i not in recent] or ok
    pool.sort(key=lambda i: (used.get(i, 0), (i * 37) % len(THEMES)))
    return [(i, used.get(i, 0)) for i in pool[:n]]


def theme_for(n):
    """Theme index for board n (0-based): a fixed stride through the list, so neighbours differ and a theme comes
    back only every len(THEMES) boards, each time as a new variant."""
    k = len(THEMES)
    stride = 23 if math.gcd(23, k) == 1 else 29
    return (n * stride) % k, n // k


def draw(theme, variant, avoid=(), seed_base=0):
    """The backdrop for `theme` (index) and `variant`, avoiding the cells in `avoid` (the subject) for clouds,
    stars and props. Returns the grid and the horizon row."""
    th = THEMES[theme]
    R = random.Random(seed_base * 7919 + theme * 1009 + variant * 104729)
    h = R.randint(*th["h"])
    g = grid()
    th["sky"](g, R, h)
    th["mid"](g, R, h)
    th["ground"](g, R, h)
    av = list(avoid)
    for p in th["sky_props"]:
        p(g, R, h, av)
    for p in th["props"]:
        p(g, R, h, av)
    return g, h


if __name__ == "__main__":
    import argparse, subprocess, sys, os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from image_to_board import RGB
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", required=True)
    ap.add_argument("--variant", type=int, default=0)
    a = ap.parse_args()
    Z, cols = 5, 8
    tiles = [draw(i, a.variant)[0] for i in range(len(THEMES))]
    rows_n = (len(tiles) + cols - 1) // cols
    W, H = cols * (N * Z + 4), rows_n * (N * Z + 4)
    img = [[(30, 30, 30)] * W for _ in range(H)]
    for i, g in enumerate(tiles):
        oy, ox = (i // cols) * (N * Z + 4), (i % cols) * (N * Z + 4)
        for r in range(N):
            for c in range(N):
                for y in range(Z):
                    for x in range(Z):
                        img[oy + r * Z + y][ox + c * Z + x] = RGB[g[r][c]]
    with open(a.sheet + ".ppm", "wb") as f:
        f.write(f"P6 {W} {H} 255\n".encode())
        for row in img:
            f.write(b"".join(bytes(p) for p in row))
    subprocess.run(["sips", "-s", "format", "png", a.sheet + ".ppm", "--out", a.sheet], capture_output=True)
    os.remove(a.sheet + ".ppm")
    print(len(THEMES), "themes")
