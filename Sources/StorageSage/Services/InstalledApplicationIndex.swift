//
//  InstalledApplicationIndex.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol InstalledApplicationIndexing: Sendable {
    func bundleIdentifiers() -> Set<String>
    func invalidate()
}

final class InstalledApplicationIndex: InstalledApplicationIndexing, @unchecked Sendable {
    static let shared = InstalledApplicationIndex()

    private let lock = NSLock()
    private var cachedIdentifiers: Set<String>?

    func bundleIdentifiers() -> Set<String> {
        lock.withLock {
            if let cachedIdentifiers { return cachedIdentifiers }
            let identifiers = discoverBundleIdentifiers()
            cachedIdentifiers = identifiers
            return identifiers
        }
    }

    func invalidate() {
        lock.withLock { cachedIdentifiers = nil }
    }

    private func discoverBundleIdentifiers() -> Set<String> {
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
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
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
}
