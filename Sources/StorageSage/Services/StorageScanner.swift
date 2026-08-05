//
//  StorageScanner.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol StorageScanning: Sendable {
    func scan() -> ScanResult
}

struct StorageScanner: StorageScanning {
    private var fm: FileManager { .default }

    func scan() -> ScanResult {
        let home = fm.homeDirectoryForCurrentUser
        var candidates: [CleanupCandidate] = []
        var inaccessible: [String] = []

        addOrphanedSimulators(home: home, to: &candidates)

        let fixedTargets: [(String, String, StorageCategory, SafetyLevel, String)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode Derived Data", .xcode, .safe, "Build products and indexes. Xcode recreates them when needed."),
            ("Library/Developer/Xcode/UserData/Previews", "SwiftUI Preview Data", .xcode, .safe, "Generated preview content that Xcode can rebuild."),
            ("Library/Developer/Xcode/iOS DeviceSupport", "iOS Device Support", .xcode, .review, "Debug symbols for connected iOS versions. They are downloaded again when required."),
            (".gradle/caches", "Gradle Caches", .developer, .safe, "Downloaded and generated Gradle artifacts."),
            (".gradle/daemon", "Gradle Daemon Data", .developer, .safe, "Logs and state from Gradle daemon processes."),
            (".gradle/jdks", "Gradle-managed JDKs", .developer, .review, "JDK installations downloaded and managed by Gradle."),
            (".konan", "Kotlin/Native Toolchains", .developer, .review, "Kotlin/Native compilers and platform dependencies."),
            (".rbenv", "rbenv Installations", .developer, .review, "Ruby versions and packages managed by rbenv."),
            (".local/share", "Local Developer Data", .developer, .review, "Data created by command-line developer tools."),
            (".codex", "Codex Local Data", .developer, .review, "Local Codex state and downloaded resources.")
        ]

        for target in fixedTargets {
            let url = home.appendingPathComponent(target.0)
            if let candidate = candidate(url: url, name: target.1, category: target.2, safety: target.3, detail: target.4, strategy: .trash(url)) {
                candidates.append(candidate)
            }
        }

        addChildren(
            of: home.appendingPathComponent("Library/Caches"),
            category: .caches,
            safety: .safe,
            detail: "Temporary application data. The owning app may download or recreate it.",
            minimumSize: 5_000_000,
            to: &candidates,
            inaccessible: &inaccessible
        )
        addChildren(
            of: home.appendingPathComponent(".cache"),
            category: .developer,
            safety: .safe,
            detail: "Rebuildable cache created by a command-line developer tool.",
            minimumSize: 5_000_000,
            to: &candidates,
            inaccessible: &inaccessible
        )
        addChildren(
            of: home.appendingPathComponent("Library/Application Support"),
            category: .appData,
            safety: .analysisOnly,
            detail: "Persistent application data. Review it in the owning app before removal.",
            minimumSize: 100_000_000,
            to: &candidates,
            inaccessible: &inaccessible
        )
        addChildren(
            of: URL(fileURLWithPath: "/Applications"),
            category: .applications,
            safety: .analysisOnly,
            detail: "Installed application. StorageSage never uninstalls apps automatically.",
            minimumSize: 20_000_000,
            to: &candidates,
            inaccessible: &inaccessible
        )

        let protected = ["Library/Mail", "Library/Messages", ".Trash"]
        for path in protected {
            let url = home.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path), !fm.isReadableFile(atPath: url.path) {
                inaccessible.append(url.path)
            }
        }

        candidates.sort { $0.size > $1.size }
        return ScanResult(
            candidates: candidates,
            volume: volumeSnapshot(),
            inaccessiblePaths: Array(Set(inaccessible)).sorted(),
            scannedAt: Date()
        )
    }

    private func addOrphanedSimulators(home: URL, to candidates: inout [CleanupCandidate]) {
        let devices = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        guard let children = try? fm.contentsOfDirectory(at: devices, includingPropertiesForKeys: nil) else { return }
        guard let installed = installedRuntimeIdentifiers(), !installed.isEmpty else { return }
        var orphanedSize: Int64 = 0
        var orphanedCount = 0

        for child in children {
            let plist = child.appendingPathComponent("device.plist")
            guard
                let data = try? Data(contentsOf: plist),
                let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let dictionary = object as? [String: Any],
                let runtime = dictionary["runtime"] as? String,
                !installed.contains(runtime)
            else { continue }
            orphanedCount += 1
            orphanedSize += allocatedSize(of: child)
        }

        guard orphanedCount > 0 else { return }
        candidates.append(CleanupCandidate(
            id: "orphaned-simulators",
            name: "Unavailable Simulator Devices",
            detail: "\(orphanedCount) devices belong to iOS runtimes that are no longer installed.",
            path: devices.path,
            category: .simulators,
            safety: .safe,
            strategy: .deleteUnavailableSimulators,
            size: orphanedSize,
            modifiedAt: modificationDate(of: devices)
        ))
    }

    private func installedRuntimeIdentifiers() -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "runtimes", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let runtimes = json["runtimes"] as? [[String: Any]]
            else { return nil }
            return Set(runtimes.compactMap { runtime in
                guard (runtime["isAvailable"] as? Bool) != false else { return nil }
                return runtime["identifier"] as? String
            })
        } catch {
            return nil
        }
    }

    private func addChildren(
        of directory: URL,
        category: StorageCategory,
        safety: SafetyLevel,
        detail: String,
        minimumSize: Int64,
        to candidates: inout [CleanupCandidate],
        inaccessible: inout [String]
    ) {
        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            if fm.fileExists(atPath: directory.path) { inaccessible.append(directory.path) }
            return
        }

        for child in children {
            let size = allocatedSize(of: child)
            guard size >= minimumSize else { continue }
            candidates.append(CleanupCandidate(
                id: child.path,
                name: friendlyName(child.deletingPathExtension().lastPathComponent),
                detail: detail,
                path: child.path,
                category: category,
                safety: safety,
                strategy: safety == .analysisOnly ? .none : .trash(child),
                size: size,
                modifiedAt: modificationDate(of: child)
            ))
        }
    }

    private func candidate(
        url: URL,
        name: String,
        category: StorageCategory,
        safety: SafetyLevel,
        detail: String,
        strategy: CleanupStrategy
    ) -> CleanupCandidate? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let size = allocatedSize(of: url)
        guard size > 0 else { return nil }
        return CleanupCandidate(
            id: url.path,
            name: name,
            detail: detail,
            path: url.path,
            category: category,
            safety: safety,
            strategy: strategy,
            size: size,
            modifiedAt: modificationDate(of: url)
        )
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let root = try? url.resourceValues(forKeys: keys) else { return 0 }
        if root.isSymbolicLink == true { return 0 }
        if root.isRegularFile == true {
            return Int64(root.totalFileAllocatedSize ?? root.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func friendlyName(_ raw: String) -> String {
        let known: [String: String] = [
            "com.spotify.client": "Spotify Cache",
            "com.openai.codex": "Codex Cache",
            "org.swift.swiftpm": "Swift Package Manager",
            "go-build": "Go Build Cache",
            "tuist-cloud": "Tuist Cloud Cache",
            "codex-runtimes": "Codex Runtimes"
        ]
        if let value = known[raw] { return value }
        return raw
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "org.", with: "")
            .replacingOccurrences(of: ".", with: " · ")
    }

    private func volumeSnapshot() -> VolumeSnapshot {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        return VolumeSnapshot(
            total: Int64(values?.volumeTotalCapacity ?? 0),
            available: Int64(values?.volumeAvailableCapacity ?? 0)
        )
    }
}
