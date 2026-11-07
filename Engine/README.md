# ChipmunkEngine

The game's rules, timed ant simulation, level builder and solver in Swift, ported 1:1 from the
`<script id="engine">` block of `web/chipmunk-challenge.html`. No UI: the native iOS app draws on top of it.

| File | What it holds |
|---|---|
| `Random.swift` | `RNG`, the seeded generator (bit-identical to the JS `rngFrom`) |
| `Level.swift` | Palette, `Art` (parsed picture), `Level` (board + navigation grid), `assembleLevel` |
| `Difficulty.swift` | Challenge settings and the 170-board Level Play ramp |
| `State.swift` | Board state, exposure, nests and slots, tapping, magic wand, Acorn Drop, rescue |
| `Simulation.swift` | The timed simulation: ant routes, release clock, `advanceTo` / `settleTimed` |
| `Generator.swift` | Player model, solution sequence, lane tuning, `generateLevel` |
| `Solver.swift` | `solve`: the stored plan, then a depth-first search |
| `Mechanics.swift` | When rocks and the locked slot appear, and where rocks go |
| `Pickups.swift` | Mystery boxes: how many a board gets and which 3x3 patch each sits on |

## Tests

```
cd Engine && swift test -c release
```

The tests load the original JavaScript engine from the HTML into JavaScriptCore and check that Swift produces the
same random numbers, pictures, solution sequences, finished boards, ant-by-ant simulation traces and solver answers.
They take about four minutes, mostly in the JavaScript side. Run them in release mode; debug is much slower.

Until the native app replaces it, the HTML stays the reference: change gameplay there first, then port the change
and rerun the tests.

## Levels

`Resources/levels.json` holds every picture: the 170 Level Play boards (9 packs), 13 background variants of each of
the 20 Coin Mining pictures, and the 5 pre-built boards. `LevelCatalog` loads it and gives each board its rocks,
locked slot, challenge, seed and aim the same way the web game does, so a board index builds the same board in both.

The pictures are painted by code in the HTML, so they are exported rather than ported:

```
tools/export_levels.sh
```

Rerun it whenever pictures or packs change in the HTML. `CatalogTests.testExportIsUpToDate` fails until you do.

Coin Mining in the web game repaints the background on every lap with no end. The native catalog stops at 13 variants
(260 distinct rounds) and then repeats them.
