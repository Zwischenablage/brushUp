# Pelican: Disk Visualizer for macOS

A native Apple Silicon app for macOS 13+, written in Swift and SwiftUI. It maps where your disk space goes and helps you get it back.

## Features

| Area | What you get |
| --- | --- |
| **Sidebar** | Mounted volumes with capacity bars, Favorites (Home, Desktop, Documents, Downloads, Pictures, Movies, Applications), Library & Caches, and Developer presets (DerivedData, Archives, DeviceSupport, Simulators, Docker, Ollama, Hugging Face, npm, Gradle, Cargo, Homebrew). Each preset shows its size, measured in the background. Presets that don't exist on your Mac are hidden. |
| **Visualization** | A neon "holographic" **sunburst** or a squarified **cushion treemap** (⌘1 / ⌘2), coloured by file category. Hovering shows a glow and an info pill (`name · size · % of parent`) and highlights the matching row in the table. Clicking zooms in. Clicking the centre, pressing ⌘↑, using the breadcrumb or pinching zooms out. The depth slider sets how many rings or nesting levels are shown. |
| **Detail table** | Lists the children of the focused folder. Columns: icon, name, package badge, size with an inline bar, recursive item count, last modified (orange if older than a year), kind, and a trash button that appears on hover. Sort by any column. |
| **Deletion** | Right-click any segment, tile or row. Move to Trash (⌘⌫, undo with ⌘Z), Delete Permanently with confirmation (⌥⌘⌫), Reveal in Finder (⌘R), Quick Look (Space or ⌘Y). The map updates in place, with no rescan. |
| **Purge Basket** | Stage items with ⌘B, the context menu, or by dragging table rows onto the basket pill. Shows a live "space to be freed" total, then sends everything to the Trash at once (⇧⌘⌫). |
| **Cleanup Suggestions** | Scans the current tree for app caches, Xcode DerivedData, `node_modules`, DeviceSupport, Archives, Python and Gradle caches, logs and crash reports, old installers (`.dmg`, `.pkg`, `.xip`, `.zip`), and files over 500 MB untouched for 6+ months. Each one is marked **SAFE** (regenerated automatically) or **REVIEW**. |
| **Uninstall Apps** | Every app in `/Applications` and `~/Applications`, with bundle size, last-opened date (from Spotlight) and leftover support files in `~/Library` (Application Support, Caches, Containers, Preferences, Saved State, WebKit…). Uninstall moves the app and the leftovers you select to the Trash. Apple apps are protected. |
| **Safety** | Hard blocks on `/System`, `/bin`, `/sbin`, `/usr` (except `/usr/local`), volume roots, the home folder, Keychains, and the top-level system and home folders. Device backups, iCloud Drive, Mail, Messages, Photos, app containers and `/Applications` get a warning badge and ask for confirmation. |
| **Full Disk Access** | Onboarding sheet that detects whether access is granted and opens the right page in System Settings. |

## Build & run

You need Xcode 15 or later (or the matching Swift 5.9+ command-line tools) on an Apple Silicon Mac.

```bash
cd Pelican
make test        # unit tests, including a real file-system scan
make app         # -> build/Pelican.app (arm64, release, ad-hoc signed)
make install     # build and copy to /Applications
open build/Pelican.app
```

`swift run Pelican` also works for quick iteration. To work in Xcode, run `open Package.swift`.

**Full Disk Access:** macOS ties the permission to the app's code signature. An ad-hoc signed build gets a new signature every time you rebuild, so you may have to re-enable access after each rebuild. To avoid this, sign with your development certificate: `SIGN_IDENTITY="Apple Development: …" make app`.

CI (`.github/workflows/pelican.yml`) builds and tests on an Apple Silicon `macos-14` runner and uploads a zipped `Pelican.app` artifact. Builds downloaded from CI are quarantined. Clear the flag with `xattr -cr Pelican.app` before opening.

## Architecture

```
Sources/Pelican
├── App/        PelicanApp (scene, menu commands), AppModel (state, caches, deletion + undo)
├── Model/      FileTree (flat contiguous node store), FileCategory, Format
├── Scanner/    BulkDirectoryReader (getattrlistbulk), DiskScanner (parallel traversal)
├── Layout/     SunburstLayout + polar hit-testing, TreemapLayout (squarified)
├── Services/   Safety guardrails, volumes/shortcuts/FDA, CleanupAdvisor, AppInventory
└── Views/      Sidebar, breadcrumb, visualization (sunburst/treemap/HUD), table, basket, cleanup, apps
```

- **Scanning:** `getattrlistbulk(2)` returns the name, type, logical size, allocated size, modification time, file ID and link count for many entries in one syscall. A pool of worker threads, one per core so both performance and efficiency cores take part, pulls directories from a shared stack. Each worker reads its directory without holding the lock and appends the results under it. Hard links are counted once. Symlinks are not followed. On `/`, firmlinked duplicates (`/System/Volumes/*`) and other volumes (`/Volumes`) are skipped.
- **Memory:** nodes are small structs in one `ContiguousArray`, linked by `Int32` indices rather than an object graph. A parent always comes before its children, so size and item-count aggregation is a single reverse sweep.
- **Rendering:** SwiftUI `Canvas` with `.drawingGroup()`, which renders offscreen through Metal. The heavy base layer is an `Equatable` view keyed on the layout, so moving the pointer only redraws a thin highlight layer. Layouts are cached by focus, tree version, metric, depth and size.
- **Live re-layout:** deleting a node marks it removed and subtracts its totals from every ancestor. The views re-lay out with a spring animation. Undo reverses this in the tree and moves the item back out of the Trash.

## Differences from the PRD

- Rendering uses SwiftUI `Canvas` composited through Metal (`drawingGroup`) instead of custom Metal shaders. It stays fluid with tens of thousands of segments. Moving to a custom `MTKView` would be the next step if needed.
- The language mode is Swift 5 (tools 5.9) for broad Xcode compatibility. It compiles fine with Swift 6 compilers.
- Size on disk uses allocated blocks (`ATTR_FILE_ALLOCSIZE`). APFS clones and Time Machine local snapshots are not deduplicated yet.
- Dragging segments directly out of the canvas into the basket isn't supported yet. You can drag table rows, or use ⌘B or the context menu.
