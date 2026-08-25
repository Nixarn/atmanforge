# AtmanForge

## Overview
AtmanForge is a macOS app for generating images with AI models. Users bring their own API keys (BYOK) — no backend or
subscription required. Replicate is currently the only provider.

## Tech Stack
- SwiftUI, `@Observable` (not Combine/ObservableObject)
- Xcode project (not SPM-based), no external dependencies
- Swift language mode 5, deployment target macOS 15.0

**macOS only.** `SUPPORTED_PLATFORMS` in the project file still lists iOS and xrOS, but the app does not build for them
— `AppState.notifyJobCompleted` and `AtmanForgeApp` use `NSApplication`, `NSFont`, and `NSColor` without `#if os(macOS)`
guards. Some other call sites are guarded; the platform list is aspirational, not real.

## Architecture
- `AtmanForge/Models/` — `ModelRegistry` (model definitions), `GenerationJob` + `ActivityRecord` (job state and its
  on-disk form), `CanvasModel` (`AspectRatio`, `ImageResolution`), `ProjectModel`
- `AtmanForge/ViewModels/AppState.swift` — the hub. Generation params, job list, library selection, undo/redo, toasts.
  Every generation funnels through the private `runGeneration(...)`.
- `AtmanForge/Services/` — `ReplicateProvider` (the only `AIProvider`), `ProjectManager` (disk I/O), `KeychainManager`,
  `ThumbnailCache`
- `AtmanForge/Views/` — sidebar (`AIGenerationPanel`) / center (Activity | Library tabs) / inspector
- `AtmanForge/Resources/Models.json` — the bundled model list

## Key Concepts

- **BYOK (Bring Your Own Keys):** Users configure their own API keys for AI providers, stored locally on-device.

- **Key storage is not the Keychain**, despite the type name `KeychainManager`. `KeychainManager.swift` imports only
  Foundation and CryptoKit — there is no `SecItem` call anywhere in the codebase. Keys are AES-GCM encrypted with a key
  derived from `SHA256(IOPlatformUUID + bundleID)` and written as a plain file. Don't describe this as Keychain storage
  in user-facing copy.

- **Models are data, not code.** `ModelRegistry` loads `Resources/Models.json`, then merges a user override from
  `Application Support/AtmanForge/Models.json` by `id` (matching id replaces, new id appends). It validates parameter
  specs and falls back to the bundled list on error. Adding a model normally means editing JSON, not Swift. Note the
  two Application Support subdirectories differ: keys live under `com.turbolynx.AtmanForge`, the model override under
  plain `AtmanForge`.

- **Batching:** models with a `nativeBatchKey` request N images in one prediction. Models without one get N separate
  predictions, created sequentially with a user-configurable throttle delay, then polled in parallel. Partial failures
  surface as a second, failed job next to the successful one.

- **The app is sandboxed** (`ENABLE_APP_SANDBOX = YES`, verified on the built product) and signed ad-hoc with no Team
  ID. So every `applicationSupportDirectory` path above actually resolves inside
  `~/Library/Containers/com.turbolynx.AtmanForge/Data/`, *not* the user's top-level Library. Check the container when a
  file "isn't there." The lack of a stable signing identity is why the app avoids the Keychain.

- **Generations are files.** Images, thumbnails, reference images, and `.activity.json` all live under the user's chosen
  project folder — outside the container, reached through a security-scoped bookmark
  (`com.apple.security.files.bookmarks.app-scope`).

## Development
- Open `AtmanForge.xcodeproj` in Xcode to build and run.
- Command line: `xcodebuild -project AtmanForge.xcodeproj -scheme AtmanForge -configuration Debug -destination 'platform=macOS' build`
- There is no test target.

## Known dead code
The Canvas layer is unreachable from the UI. `Views/Canvas/CanvasView.swift` and `Views/Canvas/ToolbarView.swift` are
referenced by nothing, and `selectedCanvasID`, `createCanvas`/`deleteCanvas`, `CanvasTool`, `canvasZoom` and the
`zoomIn`/`zoomOut`/`zoomToFit` helpers, `CanvasManifest`, and `GenerationRecord` have no path from any view.
`AspectRatio` and `ImageResolution` live in `CanvasModel.swift` but are load-bearing — don't delete those with the rest.
