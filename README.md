# OrbPuzzle V1

An independent SwiftUI + SpriteKit iOS project implementing the core 6×5 orb engine.

## Implemented

- 6 columns × 5 rows, six orb types, model/render separation
- Eight-direction swaps including direct diagonal movement
- Segment-to-grid traversal so fast horizontal, vertical, and diagonal drags do not skip cells
- 5–99 second countdown based on elapsed scene time; it starts on the first valid swap
- Configurable finger-up policy: keep playing until zero or resolve immediately
- Horizontal/vertical 3+ matching with connected-group combo counting and 5+ flags
- Non-blocking SpriteKit remove, gravity, refill, swap, and combo animations
- Exact 1–99 guaranteed skyfall combos using persistent board state
- Exactly one three-orb match group per non-blocking controlled skyfall cycle
- Remove, gravity, and refill touch only the actual matched slots; all surviving Orb IDs and types are preserved
- Safe randomized types are generated only for empty refill slots, including the final zero-match refill
- Persistent turn time, no-resolve policy, and skyfall count through `@AppStorage`
- Gameplay-only navigation edge/pan suppression, an exact 44×44 Settings button, and no gameplay overlay hit targets
- Debug-only FPS, state, time, total combo, and skyfall progress overlay
- XCTest coverage for actual removed/refill counts, preserved identities, and exact 1/10/19/99-cycle skyfall totals

## Architecture

Gameplay rendering and animation live in SpriteKit. `OrbGrid` is the source of truth and contains no SpriteKit nodes. SwiftUI hosts the menu, game scene, and settings screens.

## Build status

The project targets iOS 17. Windows cannot run Xcode or an iOS simulator, so the local iOS build and 60 FPS device runtime are **not verified**. Codemagic was not run as part of this implementation.
