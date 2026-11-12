# Chipmunk Challenge

A puzzle game, first built as a claude.ai artifact, packaged here as an iPhone app.

## Layout

| Path | What it is |
|---|---|
| `web/chipmunk-challenge.html` | The game exactly as published on claude.ai (the source of truth for gameplay). |
| `tools/make_ios_page.py` | Turns that file into the iOS page: bundled fonts, solver workbench hidden, zoom off, native haptics. |
| `ios/ChipmunkChallenge/Web/` | What ships inside the app: `index.html` plus the font files. |
| `ios/ChipmunkChallenge/*.swift` | The Swift shell: a full-screen `WKWebView` that serves the game from the app bundle and plays haptics. |
| `ios/project.yml` | XcodeGen spec that generates the Xcode project. |

## Native version (in progress)

The game is being rebuilt as a native iOS app. The app now opens the native play screen; the web shell
(`GameWebView.swift`, `Web/`) stays in the project until everything is ported.

| Path | What it is |
|---|---|
| `Engine/` | `ChipmunkEngine`, the rules, simulation, level builder and solver in Swift, tested against the HTML. See `Engine/README.md`. |
| `ios/ChipmunkChallenge/Native/` | The native play screen: `GameModel` (runs a board), `GameScene` (SpriteKit drawing and taps), `GameView` (SwiftUI header and overlays). |

Debug builds accept `-autoplay YES` as a launch argument: the board plays its own stored solution.

## Build on a Mac

```bash
brew install xcodegen
```

```bash
cd ios && xcodegen
```

```bash
open ChipmunkChallenge.xcodeproj
```

In Xcode: select the **ChipmunkChallenge** target → **Signing & Capabilities** → choose your Team. Then plug in your iPhone (or pick a simulator) and press **Run**.

The `.xcodeproj` is generated, so it isn't committed. Rerun `xcodegen` after pulling changes that add or remove files.

## Updating the game

1. Replace `web/chipmunk-challenge.html` with the newest version of the artifact.
2. Run `python3 tools/make_ios_page.py web/chipmunk-challenge.html ios/ChipmunkChallenge/Web/index.html`.
3. Build again in Xcode.

## New board packs without an app update

The app downloads new Level Play packs from GitHub Pages (`https://briangroves.github.io/chipmunkchallenge/packs/`).
App Store builds read `packs/live/manifest.json`; TestFlight and development builds read `packs/beta/manifest.json`,
so a pack can be checked on a phone before players get it. Downloads are checked against their SHA-256, saved in
Application Support, and added after every bundled board; with no network the game just plays what it has.

```bash
python3 tools/publish_pack.py make --name "Ocean Pals" --source new-boards.json --ids-file approved.txt --ratings board-ratings.csv
python3 tools/publish_pack.py promote pack-001 --push
```

`make` builds a 20-board pack from the listed ids (only boards rated 4–5 stars in Settings → Review boards) and puts
it on beta; `promote` puts it live; `status` lists the packs and their level numbers; `pull` drops a beta pack. The
site is a gh-pages checkout at `.pages/`; add `--push` to publish, otherwise the change is only committed locally.

Board numbers are the player's progress, so packs are append-only: a live pack is never removed or reordered, and
once a pack is live, new boards go out only as packs, not into `boards.json` (a test pins the bundled order). To
redraw a live board, use `make --replace OLD_ID=NEW_ID`. To try a pack locally, serve a site folder
(`python3 -m http.server`) and launch a debug build with `-packManifest http://127.0.0.1:8000/packs/beta/manifest.json`.

## Not done yet

- **Saving:** progress uses the page's local storage at the fixed origin `app://game`, so it survives app restarts but not a delete-and-reinstall. iCloud sync is a later step.
- **App icon:** add a 1024×1024 icon to an asset catalog.
- **Purchases:** if coins, hearts or tools will be sold for real money, App Store rules require In-App Purchase (StoreKit).
