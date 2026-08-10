//
//  AppLeftoverAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol AppLeftoverAnalyzing: Sendable {
    func analyze() -> [AppLeftoverRecord]
}

struct AppLeftoverAnalyzer: AppLeftoverAnalyzing {
    private let libraryURL: URL?
    private let installedBundleIdentifiers: Set<String>?
    private let fileSystem: any FileSystemInspecting
    private let exclusions: any ScanExclusionProviding

    init(
        libraryURL: URL? = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
        installedBundleIdentifiers: Set<String>? = nil,
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore()
    ) {
        self.libraryURL = libraryURL
        self.installedBundleIdentifiers = installedBundleIdentifiers
        self.fileSystem = fileSystem
        self.exclusions = exclusions
    }

    func analyze() -> [AppLeftoverRecord] {
        guard let libraryURL else { return [] }
        let installed = installedBundleIdentifiers ?? discoverInstalledBundleIdentifiers()
        let locations = [
            LeftoverLocation(component: "Caches", displayName: "Caches", suffix: nil),
            LeftoverLocation(component: "Containers", displayName: "Containers", suffix: nil),
            LeftoverLocation(component: "Preferences", displayName: "Preferences", suffix: ".plist"),
            LeftoverLocation(component: "Saved Application State", displayName: "Saved Application State", suffix: ".savedState")
        ]
        var records: [AppLeftoverRecord] = []

        for location in locations {
            let directory = libraryURL.appendingPathComponent(location.component, isDirectory: true)
            guard let children = try? fileSystem.children(of: directory) else { continue }
            for child in children {
                guard !exclusions.excludes(child) else { continue }
                let identifier = normalizedIdentifier(from: child.lastPathComponent, suffix: location.suffix)
                guard isBundleIdentifier(identifier),
                      !identifier.hasPrefix("com.apple."),
                      !installed.contains(identifier) else { continue }
                let size = fileSystem.allocatedSize(of: child)
                guard size > 0 else { continue }
                records.append(AppLeftoverRecord(
                    url: child,
                    bundleIdentifier: identifier,
                    locationName: location.displayName,
                    size: size,
                    modifiedAt: fileSystem.modificationDate(of: child)
                ))
            }
        }
        return records.sorted { $0.size > $1.size }
    }

    private func discoverInstalledBundleIdentifiers() -> Set<String> {
        let fileManager = FileManager.default
        let roots = [
            FileManager.SearchPathDomainMask.userDomainMask,
            .localDomainMask,
            .systemDomainMask
        ].flatMap { fileManager.urls(for: .applicationDirectory, in: $0) }
        var identifiers: Set<String> = []

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if let identifier = Bundle(url: url)?.bundleIdentifier {
                    identifiers.insert(identifier)
                }
                enumerator.skipDescendants()
            }
        }
        return identifiers
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
