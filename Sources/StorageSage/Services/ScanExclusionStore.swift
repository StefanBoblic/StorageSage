//
//  ScanExclusionStore.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol ScanExclusionProviding: Sendable {
    func excludedURLs() -> [URL]
}

extension ScanExclusionProviding {
    func excludes(_ url: URL) -> Bool {
        let candidatePath = url.standardizedFileURL.path
        return excludedURLs().contains { excluded in
            let excludedPath = excluded.standardizedFileURL.path
            return candidatePath == excludedPath || candidatePath.hasPrefix(excludedPath + "/")
        }
    }
}

struct UserDefaultsScanExclusionStore: ScanExclusionProviding {
    func excludedURLs() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: StoragePreferenceKeys.scanExclusions) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }

    func add(_ url: URL) {
        var paths = Set(excludedURLs().map(\.path))
        paths.insert(url.standardizedFileURL.path)
        save(paths)
    }

    func remove(path: String) {
        var paths = Set(excludedURLs().map(\.path))
        paths.remove(URL(fileURLWithPath: path).standardizedFileURL.path)
        save(paths)
    }

    private func save(_ paths: Set<String>) {
        UserDefaults.standard.set(paths.sorted(), forKey: StoragePreferenceKeys.scanExclusions)
    }
}
