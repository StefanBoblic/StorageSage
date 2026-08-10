//
//  DiskGrowthTargetProvider.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

struct DiskGrowthTarget: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
}

protocol DiskGrowthTargetProviding: Sendable {
    func targets() -> [DiskGrowthTarget]
}

struct DefaultDiskGrowthTargetProvider: DiskGrowthTargetProviding {
    private let resolvedTargets: [DiskGrowthTarget]
    private let homeDirectory: URL
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        var resolved: [DiskGrowthTarget] = []
        let definitions: [(FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask, String, String)] = [
            (.desktopDirectory, .userDomainMask, "desktop", "Desktop"),
            (.documentDirectory, .userDomainMask, "documents", "Documents"),
            (.downloadsDirectory, .userDomainMask, "downloads", "Downloads"),
            (.moviesDirectory, .userDomainMask, "movies", "Movies"),
            (.musicDirectory, .userDomainMask, "music", "Music"),
            (.picturesDirectory, .userDomainMask, "pictures", "Pictures"),
            (.cachesDirectory, .userDomainMask, "user-caches", "User Caches"),
            (.applicationSupportDirectory, .userDomainMask, "application-support", "Application Support"),
            (.applicationDirectory, .localDomainMask, "applications", "Applications")
        ]
        for (directory, domain, id, name) in definitions {
            if let url = fileManager.urls(for: directory, in: domain).first {
                resolved.append(.init(id: id, name: name, url: url))
            }
        }
        if let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            resolved.append(.init(id: "developer-data", name: "Developer Data", url: library.appendingPathComponent("Developer", isDirectory: true)))
            resolved.append(.init(id: "containers", name: "App Containers", url: library.appendingPathComponent("Containers", isDirectory: true)))
        }
        resolvedTargets = resolved
        homeDirectory = fileManager.homeDirectoryForCurrentUser
        self.environment = environment
    }

    func targets() -> [DiskGrowthTarget] {
        var targets = resolvedTargets

        let gradleRoot: URL
        if let configured = environment["GRADLE_USER_HOME"], configured.hasPrefix("/") {
            gradleRoot = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            gradleRoot = homeDirectory.appendingPathComponent(".gradle", isDirectory: true)
        }
        targets.append(.init(id: "gradle", name: "Gradle Data", url: gradleRoot))

        return Dictionary(grouping: targets, by: { $0.url.standardizedFileURL.path })
            .compactMap(\.value.first)
            .sorted { $0.name < $1.name }
    }

}
