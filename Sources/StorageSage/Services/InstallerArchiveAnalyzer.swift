//
//  InstallerArchiveAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol RecommendationAnalyzing: Sendable {
    var id: String { get }
    var title: String { get }
    func analyze() -> [CleanupCandidate]
}

protocol InstallerArchiveLocating: Sendable {
    func files(in roots: [URL], minimumSize: Int64) -> [URL]?
}

struct SpotlightInstallerArchiveLocator: InstallerArchiveLocating {
    private let commands: any CommandRunning

    init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    func files(in roots: [URL], minimumSize: Int64) -> [URL]? {
        guard let queryRoot = commonAncestor(of: roots) else { return [] }
        let extensions = ["dmg", "pkg", "xip", "zip", "ipsw", "iso"]
        let nameQuery = extensions.map { "kMDItemFSName == '*.\($0)'c" }.joined(separator: " || ")
        guard let result = commands.run(
            "mdfind",
            arguments: ["-0", "-onlyin", queryRoot.path, "(\(nameQuery)) && kMDItemFSSize >= \(minimumSize)"],
            timeout: 15
        ), result.terminationStatus == 0 else { return nil }

        return result.output.split(separator: 0).compactMap { bytes in
            guard let path = String(data: Data(bytes), encoding: .utf8) else { return nil }
            let url = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
            return roots.contains(where: { url.path.hasPrefix($0.standardizedFileURL.path + "/") }) ? url : nil
        }
    }

    private func commonAncestor(of urls: [URL]) -> URL? {
        guard var components = urls.first?.standardizedFileURL.pathComponents else { return nil }
        for url in urls.dropFirst() {
            let other = url.standardizedFileURL.pathComponents
            components = Array(zip(components, other).prefix { $0.0 == $0.1 }.map(\.0))
        }
        guard !components.isEmpty else { return nil }
        return components.reduce(URL(fileURLWithPath: "/", isDirectory: true)) {
            $1 == "/" ? $0 : $0.appendingPathComponent($1, isDirectory: true)
        }
    }
}

struct InstallerArchiveAnalyzer: RecommendationAnalyzing {
    let id = "installers"
    let title = "Installers & Archives"

    private let roots: [URL]
    private let minimumSize: Int64
    private let minimumAge: TimeInterval
    private let now: @Sendable () -> Date
    private let spotlight: (any InstallerArchiveLocating)?
    private let exclusions: any ScanExclusionProviding

    init(
        roots: [URL] = InstallerArchiveAnalyzer.defaultRoots(),
        minimumSize: Int64 = 10_000_000,
        minimumAge: TimeInterval = 30 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() },
        spotlight: (any InstallerArchiveLocating)? = SpotlightInstallerArchiveLocator(),
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore()
    ) {
        self.roots = roots.map(\.standardizedFileURL)
        self.minimumSize = minimumSize
        self.minimumAge = minimumAge
        self.now = now
        self.spotlight = spotlight
        self.exclusions = exclusions
    }

    func analyze() -> [CleanupCandidate] {
        let matcher = exclusions.matcher()
        let urls: [URL]
        if let indexed = spotlight?.files(in: roots, minimumSize: minimumSize) {
            urls = indexed
        } else {
            urls = filesystemCandidates(matcher: matcher)
        }

        let cutoff = now().addingTimeInterval(-minimumAge)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        return Dictionary(grouping: urls, by: { $0.standardizedFileURL.path })
            .compactMap(\.value.first)
            .compactMap { candidate(for: $0, cutoff: cutoff, matcher: matcher, keys: keys) }
            .sorted { $0.size > $1.size }
    }

    private func filesystemCandidates(matcher: PathExclusionMatcher) -> [URL] {
        let supportedExtensions = Self.supportedExtensions
        let skippedDirectoryNames = Self.skippedDirectoryNames
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var urls: [URL] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) && !matcher.excludes(root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                if matcher.excludes(url) {
                    enumerator.skipDescendants()
                    continue
                }
                if skippedDirectoryNames.contains(url.lastPathComponent),
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                    continue
                }
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        return urls
    }

    private func candidate(
        for url: URL,
        cutoff: Date,
        matcher: PathExclusionMatcher,
        keys: Set<URLResourceKey>
    ) -> CleanupCandidate? {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()),
              !matcher.excludes(url),
              let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let modifiedAt = values.contentModificationDate,
              modifiedAt <= cutoff else { return nil }
        let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard size >= minimumSize else { return nil }
        let ageDays = max(Calendar.current.dateComponents([.day], from: modifiedAt, to: now()).day ?? 0, 0)
        return CleanupCandidate(
            id: "installer:\(url.standardizedFileURL.path)",
            name: url.lastPathComponent,
            detail: "Installer or archive last modified \(ageDays) days ago.",
            path: url.standardizedFileURL.path,
            category: .installers,
            safety: .review,
            strategy: .trashReviewedFile(url.standardizedFileURL),
            size: size,
            modifiedAt: modifiedAt
        )
    }

    static func defaultRoots(fileManager: FileManager = .default) -> [URL] {
        [.downloadsDirectory, .desktopDirectory].flatMap {
            fileManager.urls(for: $0, in: .userDomainMask)
        }
    }

    private static let supportedExtensions: Set<String> = ["dmg", "pkg", "xip", "zip", "ipsw", "iso"]
    private static let skippedDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "Pods", ".gradle", "DerivedData", ".venv", "venv"
    ]
}
