# StorageSage

StorageSage is a native SwiftUI storage analyzer and cleanup assistant for macOS. It helps you understand where disk space went, review safe cleanup candidates, and remove selected items without sending filesystem data anywhere.

<img width="1379" height="959" alt="image" src="https://github.com/user-attachments/assets/db6bbf54-403c-4d0a-ae60-78767cc4cfe1" />

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
- Supports selecting or deselecting every detected leftover in one action.
- Keeps every result review-only until you explicitly select it for Trash.

### Smart Recommendations

- Finds stale installers and archives such as DMG, PKG, XIP, ZIP, IPSW, and ISO files.
- Detects rebuildable project artifacts from project markers instead of fixed project paths.
- Supports Swift, Node.js, CocoaPods, Gradle, and Python build artifacts and environments.
- Loads cached results immediately, analyzes sections in parallel, and publishes each section as it completes.
- Hides the completed Installers & Archives section when no matching files were found.

### APFS snapshots and history

- Inspects APFS snapshot metadata through `diskutil` without modifying snapshots.
- Keeps a local cleanup history with paths, actions, estimates, and measured free-space changes.
- Lets you clear the local history at any time.

### Disk Growth Monitor

- Records private, local snapshots of allocated storage by non-overlapping folder buckets.
- Compares the last snapshot, baseline, 24-hour, 7-day, 30-day, or complete history ranges.
- Charts used disk space and separates tracked growth from System, APFS, purgeable, and inaccessible changes.
- Uses coalesced FSEvents to remeasure only affected buckets, with a 15-minute automatic refresh limit.
- Downsamples older history and never stores file contents or a complete file listing.

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

The current downloadable release is ad-hoc signed and is not notarized. On first launch, macOS may require you to right-click the app and choose **Open**, or approve it in **System Settings → Privacy & Security**. See [Code signing](#code-signing) for development and release signing behavior.

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

Independent filesystem jobs use bounded Swift task groups. Large Files and Duplicates share an FSEvents-invalidated metadata index, directory measurements are batched, and Overview streams partial results while a scan is running. Spotlight and `du` provide fast paths with safe filesystem fallbacks. Specialized analyzers and cleanup services are injected behind protocols, while SwiftUI views remain free of filesystem side effects.

Smart Recommendations uses a Spotlight-first installer query, filters generated dependency trees, caches its latest result, and publishes each analyzer section as soon as it finishes. Cleanup screens update optimistically and perform verification refreshes without blocking the completed action.

## Build and test

Build the release application:

```sh
zsh scripts/package.sh
```

The packaged app is written to `dist/StorageSage.app` by default.

### Code signing

`scripts/package.sh` keeps the bundle identifier stable at `com.stefanboblic.StorageSage` and selects a signing identity in this order:

1. The identity supplied through `CODESIGN_IDENTITY`.
2. An installed `Apple Development` or `Developer ID Application` identity from the login Keychain.
3. An ad-hoc signature when no Apple identity is available, such as on an unconfigured CI runner.

Local builds signed with the same Apple Development certificate keep a stable designated requirement, which allows macOS to associate Files and Folders permissions with subsequent builds. An Apple Development signature is intended only for development; public distribution requires a `Developer ID Application` certificate and notarization.

To choose a release identity explicitly:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" zsh scripts/package.sh
```

Verify the resulting bundle and inspect its authority:

```sh
codesign --verify --deep --strict dist/StorageSage.app
codesign -dvvv dist/StorageSage.app
```

The packaging script signs the app but does not currently submit it to Apple's notary service. A public release must be notarized and stapled separately before publishing if a Developer ID identity is used.

Run the test suite:

```sh
swift test
```

The real-filesystem performance benchmark is opt-in:

```sh
STORAGESAGE_BENCHMARK=1 swift test --filter StoragePerformanceTests
```
