//
//  AppLeftoverAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol AppLeftoverAnalyzing: Sendable {
    func analyze() -> [AppLeftoverRecord]
    func noteFileChanges(_ batch: FileChangeBatch)
}

struct AppLeftoverAnalyzer: AppLeftoverAnalyzing {
    private let libraryURL: URL?
    private let installedBundleIdentifiers: Set<String>?
    private let fileSystem: any FileSystemInspecting
    private let exclusions: any ScanExclusionProviding
    private let applications: any InstalledApplicationIndexing

    init(
        libraryURL: URL? = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
        installedBundleIdentifiers: Set<String>? = nil,
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore(),
        applications: any InstalledApplicationIndexing = InstalledApplicationIndex.shared
    ) {
        self.libraryURL = libraryURL
        self.installedBundleIdentifiers = installedBundleIdentifiers
        self.fileSystem = fileSystem
        self.exclusions = exclusions
        self.applications = applications
    }

    func analyze() -> [AppLeftoverRecord] {
        guard let libraryURL else { return [] }
        let installed = installedBundleIdentifiers ?? applications.bundleIdentifiers()
        let exclusionMatcher = exclusions.matcher()
        let locations = [
            LeftoverLocation(component: "Caches", displayName: "Caches", suffix: nil),
            LeftoverLocation(component: "Containers", displayName: "Containers", suffix: nil),
            LeftoverLocation(component: "Preferences", displayName: "Preferences", suffix: ".plist"),
            LeftoverLocation(component: "Saved Application State", displayName: "Saved Application State", suffix: ".savedState")
        ]
        var pending: [(URL, String, String)] = []

        for location in locations {
            let directory = libraryURL.appendingPathComponent(location.component, isDirectory: true)
            guard let children = try? fileSystem.children(of: directory) else { continue }
            for child in children {
                guard !exclusionMatcher.excludes(child) else { continue }
                let identifier = normalizedIdentifier(from: child.lastPathComponent, suffix: location.suffix)
                guard isBundleIdentifier(identifier),
                      !identifier.hasPrefix("com.apple."),
                      !installed.contains(identifier) else { continue }
                pending.append((child, identifier, location.displayName))
            }
        }
        let sizes = fileSystem.allocatedSizes(of: pending.map(\.0))
        let records = pending.compactMap { url, identifier, locationName -> AppLeftoverRecord? in
            let size = sizes[url] ?? 0
            guard size > 0 else { return nil }
            return AppLeftoverRecord(
                url: url,
                bundleIdentifier: identifier,
                locationName: locationName,
                size: size,
                modifiedAt: fileSystem.modificationDate(of: url)
            )
        }
        return records.sorted { $0.size > $1.size }
    }

    func noteFileChanges(_ batch: FileChangeBatch) {
        let fileManager = FileManager.default
        let roots = [
            FileManager.SearchPathDomainMask.userDomainMask,
            .localDomainMask,
            .systemDomainMask
        ].flatMap { fileManager.urls(for: .applicationDirectory, in: $0) }
        if batch.requiresFullRescan || batch.affects(roots) {
            applications.invalidate()
        }
    }

    private func normalizedIdentifier(from name: String, suffix: String?) -> String {
        guard let suffix, name.hasSuffix(suffix) else { return name }
        return String(name.dropLast(suffix.count))
    }

    private func isBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

private struct LeftoverLocation {
    let component: String
    let displayName: String
    let suffix: String?
}
