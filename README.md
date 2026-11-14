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

## Not done yet

- **Saving:** progress uses the page's local storage at the fixed origin `app://game`, so it survives app restarts but not a delete-and-reinstall. iCloud sync is a later step.
- **App icon:** add a 1024×1024 icon to an asset catalog.
- **Pro (version 3):** one non-consumable In-App Purchase, `com.groveseng.chipmunkchallenge.pro`, unlocks the tables,
  auto-finish, the nest queue, speed settings, the daily gift, Undo and fast-forward (`Native/ProStore.swift`). It must
  be created in App Store Connect (Features → In-App Purchases, Non-Consumable) before TestFlight or release builds can
  buy it. Xcode runs use `ios/Pro.storekit`, so purchases work locally with no account. Debug builds accept
  `-pro YES` / `-pro NO` to force either version.
