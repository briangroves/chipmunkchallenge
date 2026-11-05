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

## Tests

```
cd Engine && swift test -c release
```

The tests load the original JavaScript engine from the HTML into JavaScriptCore and check that Swift produces the
same random numbers, pictures, solution sequences, finished boards, ant-by-ant simulation traces and solver answers.
They take about four minutes, mostly in the JavaScript side. Run them in release mode; debug is much slower.

Until the native app replaces it, the HTML stays the reference: change gameplay there first, then port the change
and rerun the tests.
