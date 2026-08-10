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
    func matcher() -> PathExclusionMatcher {
        PathExclusionMatcher(urls: excludedURLs())
    }

    func excludes(_ url: URL) -> Bool {
        matcher().excludes(url)
    }
}

struct PathExclusionMatcher: Sendable {
    private let excludedPaths: [String]

    init(urls: [URL]) {
        excludedPaths = Array(Set(urls.map { $0.standardizedFileURL.path })).sorted()
    }

    func excludes(_ url: URL) -> Bool {
        excludes(path: url.standardizedFileURL.path)
    }

    func excludes(path candidatePath: String) -> Bool {
        excludedPaths.contains { excludedPath in
            candidatePath == excludedPath || candidatePath.hasPrefix(excludedPath + "/")
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
