# ArcmarkData Library Split

## Overview

The `ArcmarkData` target is a Foundation-only library extracted from `ArcmarkCore`. It contains the data model, persistence, state management, and import services — everything needed to read and write Arcmark's bookmark data without AppKit dependencies.

This split enables building a CLI tool (`arcmark`) that shares the same data layer as the GUI app, and lays the groundwork for cross-platform data access.

## Package Structure

```
ArcmarkData (Foundation-only library)
  ├── Models.swift          — AppState, Workspace, Node, Folder, Link, CustomIcon
  ├── AppModel.swift        — Central state manager, all mutation methods
  ├── DataStore.swift       — JSON persistence to ~/Library/Application Support/Arcmark/
  ├── NodeFiltering.swift   — Recursive tree search/filter
  ├── WorkspaceColor.swift  — WorkspaceColorId enum (NSColor properties behind #if canImport(AppKit))
  ├── UserDefaultsKeys.swift — Preference key constants
  ├── ArcImportService.swift — Arc browser bookmark import
  └── ChromeImportService.swift — Chrome/Firefox HTML bookmark import

ArcmarkCore (AppKit library)
  ├── depends on: ArcmarkData, Sparkle
  ├── re-exports ArcmarkData via @_exported import
  └── All UI components, view controllers, and AppKit services

ArcmarkApp (GUI executable)
  └── depends on: ArcmarkCore
```

## Key Design Decisions

### Why a separate target (not just #if canImport guards)?

`ArcmarkCore` depends on Sparkle (an AppKit auto-update framework). Even with conditional compilation guards on individual files, any target linking `ArcmarkCore` transitively pulls in Sparkle and requires AppKit. A separate Foundation-only target is the only way to avoid this.

### @MainActor on AppModel

Swift 6.2 (the project's swift-tools-version) enables strict concurrency checking. `AppModel` is a mutable class — using it from an async context without actor isolation produces compiler errors. All existing GUI call sites are already on `@MainActor` (routed through MainViewController), so this annotation is backward-compatible.

### #if canImport(AppKit) on WorkspaceColorId

The `WorkspaceColorId` enum lives in ArcmarkData because it's part of the `Workspace` model (needed for JSON encoding/decoding). Its `NSColor` computed properties (`color`, `backgroundColor`, `textColor`) are only available when AppKit is present. The raw enum values, `name`, `allCases`, `defaultColor()`, and `randomColor()` work everywhere.

### @_exported import

`ArcmarkCore` re-exports `ArcmarkData` via `ArcmarkDataExports.swift`, so any file importing `ArcmarkCore` automatically sees all data-layer types. This avoids requiring `import ArcmarkData` in every ArcmarkCore source file.

### Public access control

All types, properties, initializers, and methods in ArcmarkData are `public` because they must be visible across target boundaries. The mutation discipline (all changes through AppModel methods) is enforced by convention, not access control.

## What Changed (for reviewers)

This is a **pure refactor** — zero behavior changes:

- **8 files moved** from `Sources/ArcmarkCore/` to `Sources/ArcmarkData/` via `git mv`
- **1 file extracted** — `UserDefaultsKeys` split out of `Constants.swift`
- **1 file created** — `ArcmarkDataExports.swift` for `@_exported import`
- **~150 declarations** marked `public` (structs, enums, properties, methods, initializers)
- **`Sendable` conformances** added to value types that were already effectively sendable
- **Explicit `public init`** added to structs where Swift doesn't synthesize public memberwise initializers
- **`self.`** added in AppModel closures (required by `@MainActor` for explicit self in escaping closures)
- **`import AppKit` → `import Foundation`** in ArcImportService (it never used AppKit types)
- **Test files** gained `@testable import ArcmarkData` and `@MainActor` annotations

## Verification

- `swift build` succeeds for all targets (ArcmarkData, ArcmarkCore, ArcmarkApp)
- `swift test` passes all 15 existing tests with zero regressions
- The GUI app launches and operates normally
