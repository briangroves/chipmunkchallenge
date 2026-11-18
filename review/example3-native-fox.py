"""A fox drawn block by block at board size, on the converter's backdrop, for comparison."""
import json, os, subprocess, sys
sys.path.insert(0, "/Users/briangroves/Developer/chipmunkchallenge/tools")
import image_to_board as t

S = os.path.dirname(os.path.abspath(__file__))

# Left half of a sitting, front-facing fox (16 wide); mirrored to 32. '.' is see-through.
LEFT = [
    ".....KK.........",
    "....KNNK........",
    "....KNNNK.......",
    "...KOONPK.......",
    "...KOPPPOK......",
    "..KOOPPPOOKKKKKK",
    "..KOOPPOOOOOOOOO",
    "..KOOOOOOOOOOOOO",
    ".KOOOOOOOOOOOOOO",
    ".KOOOOOKWOOOOOOO",
    ".KOOOOOKKOOOOOOO",
    ".KWOOOOOOOOOOOOO",
    ".KWWWOOOOOOOOOOO",
    "..KWWWWWWOOOOOOK",
    "...KWWWWWWWWWWWK",
    "....KKWWWWWWWWKW",
    ".....KOOWWWWWWWW",
    ".....KOOOWWWWWWW",
    "....KOOOOWWWWWWW",
    "....KOOOOOWWWWWW",
    "....KOOOOOWWWWWW",
    "...KOOOOOOOWWWWW",
    "...KOOOOOOKOOOOK",
    "...KOOOOOOKOOOOK",
    "...KOOOOOOKNNNNK",
    "....KKKKKKKKKKKK",
]
assert all(len(r) == 16 for r in LEFT)
FOX = [r + r[::-1] for r in LEFT]

# A bushy tail curling round the right side, with a white tip, drawn over the mirrored body.
TAIL = {
    16: "..........KKK.",
    17: ".........KOOOK",
    18: "........KOOOOK",
    19: "........KOOOOK",
    20: "........KOOOOK",
    21: ".......KOOOOOK",
    22: "......KOOOOOWK",
    23: ".....KOOOOOWWK",
    24: "....KOOOOWWWWK",
    25: "....KKKKKKKKK.",
}
for r, s in TAIL.items():
    row = list(FOX[r] + "." * 14)
    for i, ch in enumerate(s):
        if ch != ".":
            row[24 + i] = ch
    FOX[r] = "".join(row)

LEFT0, TOP0 = 2, 11
cells = {}
for r, row in enumerate(FOX):
    for c, ch in enumerate(row):
        if ch != "." and 0 <= LEFT0 + c < t.N:
            cells[(TOP0 + r, LEFT0 + c)] = ch
g = t.backdrop()
t.place_cloud(g, list(cells))
t.flowers(g, list(cells))
for (r, c), k in cells.items():
    g[r][c] = k
rows = ["".join(r) for r in g]
json.dump({"name": "Fox (drawn at board size)", "rows": rows}, open(os.path.join(S, "fox-native.json"), "w"), indent=1)

# Quick preview: a PPM scaled 10x, converted to PNG with sips.
Z = 10
with open(os.path.join(S, "fox-native.ppm"), "wb") as f:
    f.write(f"P6 {t.N * Z} {t.N * Z} 255\n".encode())
    for r in range(t.N):
        line = b"".join(bytes(t.RGB[ch]) * Z for ch in rows[r])
        f.write(line * Z)
subprocess.run(["sips", "-s", "format", "png", os.path.join(S, "fox-native.ppm"), "--out",
                os.path.join(S, "fox-native.png")], capture_output=True)
print("\n".join(rows))
