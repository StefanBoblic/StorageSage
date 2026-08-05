//
//  WhitelistStore.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol WhitelistProviding: Sendable {
    func whitelistedURLs() -> [URL]
}

struct UserDefaultsWhitelistStore: WhitelistProviding {
    func whitelistedURLs() -> [URL] {
        UserDefaults.standard.stringArray(forKey: StoragePreferenceKeys.whitelist, defaultValue: [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }

    func add(_ url: URL) {
        var paths = Set(whitelistedURLs().map(\.path))
        paths.insert(url.standardizedFileURL.path)
        save(paths)
    }

    func remove(path: String) {
        var paths = Set(whitelistedURLs().map(\.path))
        paths.remove(URL(fileURLWithPath: path).standardizedFileURL.path)
        save(paths)
    }

    private func save(_ paths: Set<String>) {
        UserDefaults.standard.set(paths.sorted(), forKey: StoragePreferenceKeys.whitelist)
    }
}

private extension UserDefaults {
    func stringArray(forKey key: String, defaultValue: [String]) -> [String] {
        stringArray(forKey: key) ?? defaultValue
    }
}
