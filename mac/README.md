# Satz for Mac

A native macOS app (SwiftUI, AppKit canvas) on the Rust engine in `engine/`, bound
to Swift with UniFFI. macOS 15 or later.

## Build

Needs Xcode 26, stable Rust with the `aarch64-apple-darwin` and `x86_64-apple-darwin`
targets, and `xcodegen` (`brew install xcodegen`).

```sh
mac/build-engine          # Rust engine -> mac/SatzEngine (xcframework + Swift bindings)
cd mac && xcodegen        # project.yml -> Satz.xcodeproj
open Satz.xcodeproj
```

The scheme's `Engine` target runs `build-engine` before every build (`release`
builds a universal binary), so after the first run Xcode keeps it up to date.

## Layout

- `SatzEngine/` – Swift package: `SatzEngine` (generated bindings), `SatzCore`
  (snapshot models, commands, engine wrapper) and its tests (`swift test`).
- `Satz/` – the app: `App/` document and menus, `Editor/` window state, `Views/`.
- `SatzTests/`, `SatzUITests/` – unit and XCUITest tests (`xcodebuild test -scheme Satz`).

## Rules

- A document lives on the main actor: the engine keeps fonts, images and the colour
  profile per thread (`engine/src/native.rs` panics off the owning thread). Exports
  load the saved bytes into an engine of their own thread.
- Every change goes through `Editor.apply`; each engine undo step registers one
  action in the window's `UndoManager`, so Edit ▸ Undo, the edited mark and autosave
  follow the engine.
- Display lists cross as little-endian words (`Data`), commands and snapshots as JSON.
- The canvas (`Satz/Canvas`) draws the spread in 512 pt tiles on background threads
  with `SatzCore.Painter` (Core Graphics); while a zoom changes it scales the tiles it
  has and draws new ones once the zoom rests. Fonts and images load on the main actor
  (`Resources`), painters only read them.
- CMYK documents show as they print: the canvas draws the inverted C, M and Y plate
  and the K plate (`Engine.plate`) and turns them into screen colours through the
  profile's table (`InkTable`), as the web app's `INKS` shader does.
- `PainterTests` compare the canvas with the engine's PNG of every example page.
- UI tests run the app in English (`-AppleLanguages (en)`); their screenshots are in
  the test result (`xcrun xcresulttool export attachments`).
