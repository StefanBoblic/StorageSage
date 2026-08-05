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
