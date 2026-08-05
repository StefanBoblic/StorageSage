# StorageSage

StorageSage is a native SwiftUI storage analyzer and cleanup assistant for macOS.

## Install with Homebrew

```sh
brew install --cask stefanboblic/tap/storagesage
```

The downloadable app is currently ad-hoc signed rather than notarized with an
Apple Developer ID certificate. On first launch, macOS may require you to
right-click the app and choose **Open**, or approve it in **System Settings →
Privacy & Security**.

## Architecture

The app follows MVVM with explicit dependency boundaries:

```text
App/          Composition root and dependency injection
Models/       Domain and presentation data structures
Services/     Filesystem scanning and cleanup side effects
ViewModels/   Observable UI state and service orchestration
Views/        SwiftUI screens and reusable components
```

`StorageScanner` is path-agnostic. Scan locations are supplied through
`ScanTargetProviding`, system folders are resolved with `FileManager` search-path
APIs, and developer-specific locations live in a declarative rule catalog.
Specialized analysis, such as unavailable Simulator devices, is isolated behind
`StorageAnalyzing` and injected into the scanner.

Independent filesystem jobs use a bounded Swift task group. The global limit is
configurable in Settings, so large cache roots can be measured concurrently
without creating an unbounded number of filesystem walkers.

Before cleanup, every candidate passes through `DeletionPolicy`. The policy
rejects protected macOS and user-data locations, resolves symlinks, blocks path
traversal, and honors the persistent user whitelist. Dry Run validates the same
pipeline and reports estimated reclaimable space without changing files.

Xcode and Gradle locations are resolved dynamically when possible. StorageSage
reads Xcode's custom Derived Data preference and `GRADLE_USER_HOME`, then falls
back to standard macOS locations.

`StorageViewModel` owns the screen state and depends on the `StorageScanning` and
`StorageCleaning` protocols. Views never scan or mutate the filesystem directly.

## Safety model

- Rebuildable caches are moved to Trash.
- Persistent application data and installed apps are analysis-only.
- Unavailable Simulator devices use the official `xcrun simctl delete unavailable` command and require confirmation.
- No cleanup runs automatically.

## Build

```sh
zsh scripts/package.sh
```

The packaged app is written to `dist/StorageSage.app` by default.
