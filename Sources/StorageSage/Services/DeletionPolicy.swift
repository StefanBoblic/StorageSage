//
//  DeletionPolicy.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

enum DeletionDecision: Equatable, Sendable {
    case allowed
    case denied(String)
}

protocol DeletionPolicyEvaluating: Sendable {
    func evaluate(_ candidate: CleanupCandidate) -> DeletionDecision
}

struct DefaultDeletionPolicy: DeletionPolicyEvaluating {
    private let whitelist: any WhitelistProviding

    init(whitelist: any WhitelistProviding = UserDefaultsWhitelistStore()) {
        self.whitelist = whitelist
    }

    func evaluate(_ candidate: CleanupCandidate) -> DeletionDecision {
        guard candidate.safety != .analysisOnly, candidate.strategy != .none else {
            return .denied("This item is analysis-only.")
        }

        let url: URL
        switch candidate.strategy {
        case .trash(let targetURL):
            url = targetURL
        case .deleteUnavailableSimulators:
            url = URL(fileURLWithPath: candidate.path, isDirectory: true)
        case .none:
            return .denied("This item is analysis-only.")
        }

        let rawPath = url.path
        guard rawPath.hasPrefix("/"), !rawPath.isEmpty else {
            return .denied("Only absolute paths can be removed.")
        }
        guard !rawPath.components(separatedBy: "/").contains("..") else {
            return .denied("Path traversal components are not allowed.")
        }
        guard rawPath.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return .denied("The path contains control characters.")
        }
        guard candidate.path == rawPath else {
            return .denied("The cleanup target does not match the scanned path.")
        }

        let literalURL = url.standardizedFileURL
        let resolvedURL = literalURL.resolvingSymlinksInPath()
        if isWhitelisted(literalURL) || isWhitelisted(resolvedURL) {
            return .denied("The item is protected by your whitelist.")
        }
        let protected = protectedLocations()
        let matchesExactRoot = protected.exact.contains { root in
            literalURL.standardizedFileURL.path == root.path || resolvedURL.standardizedFileURL.path == root.path
        }
        let matchesProtectedSubtree = protected.subtrees.contains { root in
            contains(literalURL, in: root) || contains(resolvedURL, in: root)
        }
        if matchesExactRoot || matchesProtectedSubtree {
            return .denied("StorageSage protects this location from deletion.")
        }

        return .allowed
    }

    private func isWhitelisted(_ url: URL) -> Bool {
        whitelist.whitelistedURLs().contains { contains(url, in: $0.resolvingSymlinksInPath()) }
    }

    private func protectedLocations() -> (exact: [URL], subtrees: [URL]) {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var exact = [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/Users", isDirectory: true),
            home
        ]
        var subtrees = [
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/usr", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true),
            URL(fileURLWithPath: "/etc", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true),
            home.appendingPathComponent(".Trash", isDirectory: true)
        ]

        for directory in [
            FileManager.SearchPathDirectory.desktopDirectory,
            .documentDirectory,
            .downloadsDirectory,
            .moviesDirectory,
            .musicDirectory,
            .picturesDirectory
        ] {
            subtrees.append(contentsOf: fileManager.urls(for: directory, in: .userDomainMask))
        }

        if let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            exact.append(library)
            for component in ["Mail", "Messages", "Keychains", "Safari", "HomeKit"] {
                subtrees.append(library.appendingPathComponent(component, isDirectory: true))
            }
        }
        return (
            exact.map { $0.standardizedFileURL },
            subtrees.map { $0.standardizedFileURL }
        )
    }

    private func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if candidatePath == rootPath { return true }
        return candidatePath.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }
}
