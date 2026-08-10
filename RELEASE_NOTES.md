# StorageSage 1.3.0

StorageSage 1.3.0 adds private disk-growth tracking and makes the existing analysis workflows faster and more responsive. All history and filesystem analysis remain local to the Mac.

## Disk Growth Monitor

- Added local storage snapshots for Desktop, Documents, Downloads, media, caches, Application Support, applications, containers, and developer data.
- Added used-space charts and comparisons against the last snapshot, a baseline, 24 hours, 7 days, 30 days, or the complete retained history.
- Separates tracked folder changes from unattributed System, APFS, purgeable, and inaccessible storage changes.
- Uses coalesced FSEvents to remeasure only affected buckets and limits automatic snapshots to once every 15 minutes.
- Keeps detailed recent history, downsamples older snapshots, and never stores file contents or a complete file listing.

## Faster analysis

- Added bounded parallel filesystem work and batched directory-size measurements.
- Added a shared, FSEvents-invalidated metadata index for Large Files and Duplicate Finder.
- Added Spotlight-first installer discovery with a safe filesystem fallback.
- Smart Recommendations now loads cached results immediately, runs analyzers in parallel, and publishes each section as it completes.
- Overview now streams progress and partial results while the live scan is running.
- Cleanup screens update optimistically and avoid unnecessary full rescans after successful removal.
- Hardened command output handling so large Spotlight results cannot block child processes.

## Interface and workflow improvements

- Added Select All and Deselect All to App Leftovers.
- Empty Installers & Archives recommendations are hidden after analysis completes.
- Fixed toolbar refresh buttons showing a spinner and refresh icon simultaneously.
- Fixed empty tab content moving to the vertical center of the window.
- Added stable local Apple Development signing discovery and a persistent `com.stefanboblic.StorageSage` bundle identifier.
- Improved packaging around Finder and File Provider metadata.

## Measured performance

On the audited development Mac:

- Installers & Archives: approximately 0.77 seconds.
- Project Artifacts: approximately 3.63 seconds, running in parallel with installer analysis.
- Overview: approximately 10.29 seconds for 76 real candidates, with cached and progressive results displayed immediately.

Results depend on disk size, directory contents, Spotlight state, and filesystem permissions.

## Requirements and installation

- macOS 14 Sonoma or later
- Apple silicon Mac

Install or upgrade with Homebrew:

```sh
brew upgrade --cask stefanboblic/tap/storagesage
```

The public ZIP remains ad-hoc signed and is not notarized because a Developer ID Application certificate is not configured for distribution. Local development builds use an installed Apple Development identity when available. Because version 1.3.0 changes the bundle identifier and signing identity, macOS may request Files and Folders permissions once again after upgrading; subsequent builds with the same identity should retain them.
