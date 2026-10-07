# OrbPuzzle V1

An independent SwiftUI + SpriteKit iOS project implementing the core 6×5 orb engine.

## Implemented

- 6 columns × 5 rows, six orb types, model/render separation
- Eight-direction swaps including direct diagonal movement
- Segment-to-grid traversal so fast horizontal, vertical, and diagonal drags do not skip cells
- 5–99 second countdown based on elapsed scene time; it starts on the first valid swap
- Finger-up ends only the current drag; the timed session and board remain active until zero
- Horizontal/vertical 3+ matching with connected-group combo counting and 5+ flags
- Non-blocking SpriteKit remove, gravity, refill, swap, and combo animations
- Normal independent RNG and weighted High Combo RNG
- Configurable 1–99 cascade rounds with early stop on no match
- Persistent turn time, cascade rounds, and drop mode through `@AppStorage`
- Persistent 1–99 target combo with HUD display
- Gameplay-only interactive-pop suppression, an exact 44×44 Settings button, and no gameplay overlay hit targets
- Debug-only FPS, state, time, combo, cascade, and mode overlay
- XCTest coverage for matching, movement, traversal, timer, gravity, board generation, and cascade bounds

## Architecture

Gameplay rendering and animation live in SpriteKit. `OrbGrid` is the source of truth and contains no SpriteKit nodes. SwiftUI hosts the menu, game scene, and settings screens.

## Build status

The project targets iOS 17. Windows cannot run Xcode or an iOS simulator, so the local iOS build and 60 FPS device runtime are **not verified**. Codemagic is intentionally not configured or run.
