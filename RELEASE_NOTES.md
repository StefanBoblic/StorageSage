# StorageSage 1.2.0

This release expands StorageSage from a cache cleaner into a broader, faster disk analysis toolkit while keeping cleanup reviewable and local.

## Highlights

- Added an on-demand Large Files scanner with configurable thresholds, size/age sorting, a Spotlight fast path, and filesystem fallback.
- Added a Duplicate Finder with staged SHA-256 verification, bounded parallel hashing, hard-link awareness, and safeguards that preserve at least one copy.
- Added App Leftovers analysis based on bundle identifiers and installed applications.
- Added Smart Recommendations for stale installers, archives, and rebuildable Swift, Node.js, CocoaPods, Gradle, and Python project artifacts.
- Added a read-only APFS Snapshot Inspector based on `diskutil` metadata.
- Added local Cleanup History with estimated bytes, cleanup actions, affected paths, and the measured change in available disk space.
- Added Deep Scan exclusions for Large Files, Duplicates, Recommendations, and App Leftovers.

## Accuracy and safety

- Cleanup totals are remeasured immediately before confirmation.
- The interface now distinguishes bytes moved to Trash from bytes deleted immediately.
- Cleanup results report the actual before/after change in available disk space.
- Duplicate candidates are fully re-verified before confirmation and immediately before cleanup.
- Selection is temporarily locked while estimates refresh, and stale cleanup progress no longer carries into a new operation.
- Cleanup remains opt-in, protected paths are rejected, and user files are moved to Trash whenever possible.

## Performance and interface

- Added bounded parallel scanning and hashing with a configurable concurrency limit.
- Added cached Overview results followed by a live refresh.
- Added `du` and Spotlight fast paths with safe filesystem fallbacks.
- Added FSEvents-based stale-result tracking for Large Files.
- Fixed the Large Files sidebar icon and refreshed the release documentation.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon Mac

Install with Homebrew:

```sh
brew install --cask stefanboblic/tap/storagesage
```

The downloadable build is ad-hoc signed and is not Apple-notarized yet. On first launch, right-click the app and choose **Open**, or approve it in **System Settings → Privacy & Security** if macOS blocks it.
