# StorageSage

StorageSage is a native SwiftUI storage analyzer and cleanup assistant for macOS. It helps you understand where disk space went, review safe cleanup candidates, and remove selected items without sending filesystem data anywhere.

<img width="1539" height="1006" alt="StorageSage overview" src="https://github.com/user-attachments/assets/7fc47adf-396a-4d98-a193-8e236fc37e98" />

## Requirements

- macOS 14 Sonoma or later
- Apple silicon Mac

## Features

### Storage overview and cleanup

- Scans common macOS, application, and developer cache locations.
- Uses a cached overview for a fast initial display, followed by a live refresh.
- Shows an exact pre-cleanup estimate and refreshes the overview after cleanup.
- Separates items moved to Trash from items deleted immediately.
- Reports the actual change in available disk space after every cleanup.
- Supports Dry Run, persistent exclusions, and configurable scan concurrency.

### Large Files

- Finds large files in personal folders on demand.
- Offers 100 MB, 500 MB, and 1 GB thresholds.
- Sorts results by size or age.
- Uses Spotlight when available and falls back to a filesystem scan.
- Uses FSEvents to mark saved results stale when the filesystem changes.

### Duplicate Finder

- Groups candidates by size, partial SHA-256, and then full SHA-256.
- Runs hashing with bounded concurrency and recognizes hard links.
- Prevents selecting every copy in a duplicate group.
- Re-verifies files before confirmation and again immediately before cleanup.

### App Leftovers

- Finds support files that may remain after an app is uninstalled.
- Matches installed applications by bundle identifier and ignores Apple-owned identifiers.
- Keeps every result review-only until you explicitly select it for Trash.

### Smart Recommendations

- Finds stale installers and archives such as DMG, PKG, XIP, ZIP, IPSW, and ISO files.
- Detects rebuildable project artifacts from project markers instead of fixed project paths.
- Supports Swift, Node.js, CocoaPods, Gradle, and Python build artifacts and environments.

### APFS snapshots and history

- Inspects APFS snapshot metadata through `diskutil` without modifying snapshots.
- Keeps a local cleanup history with paths, actions, estimates, and measured free-space changes.
- Lets you clear the local history at any time.

## Safety and privacy

- Nothing is removed automatically.
- Rebuildable caches and reviewed files are moved to Trash whenever possible.
- Persistent application data and installed apps remain analysis-only.
- Unavailable Simulator devices are removed only after confirmation through the official `xcrun simctl delete unavailable` command.
- Every candidate passes a deletion policy that resolves symlinks, rejects protected locations and path traversal, and honors your deletion whitelist.
- Deep Scan exclusions are separate from the deletion whitelist and apply to Large Files, Duplicates, Recommendations, and App Leftovers.
- All analysis runs locally. StorageSage does not upload file names, paths, or contents.

## Install with Homebrew

```sh
brew install --cask stefanboblic/tap/storagesage
```

You can also download the latest ZIP from [GitHub Releases](https://github.com/StefanBoblic/StorageSage/releases/latest), extract it, and move `StorageSage.app` to Applications.

The downloadable app is currently ad-hoc signed rather than notarized with an Apple Developer ID certificate. On first launch, macOS may require you to right-click the app and choose **Open**, or approve it in **System Settings → Privacy & Security**.

## Architecture

The app follows MVVM with explicit dependency boundaries:

```text
App/          Composition root and dependency injection
Models/       Domain and presentation data structures
Services/     Filesystem scanning and cleanup side effects
ViewModels/   Observable UI state and service orchestration
Views/        SwiftUI screens and reusable components
```

`StorageScanner` is path-agnostic. Scan locations come from `ScanTargetProviding`; system folders are resolved through `FileManager` search-path APIs; developer locations are described by a rule catalog. Xcode's custom Derived Data preference and `GRADLE_USER_HOME` are resolved dynamically.

Independent filesystem jobs use bounded Swift task groups. Large Files uses Spotlight as a fast path, directory sizing can use `du`, and both have safe filesystem fallbacks. Specialized analyzers and cleanup services are injected behind protocols, while SwiftUI views remain free of filesystem side effects.

## Build and test

Build the release application:

```sh
zsh scripts/package.sh
```

The packaged app is written to `dist/StorageSage.app` by default.

Run the test suite:

```sh
swift test
```

The real-filesystem performance benchmark is opt-in:

```sh
STORAGESAGE_RUN_BENCHMARKS=1 swift test --filter InitialScanPerformanceTests
```
