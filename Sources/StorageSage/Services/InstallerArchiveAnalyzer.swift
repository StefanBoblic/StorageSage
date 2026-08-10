//
//  InstallerArchiveAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol RecommendationAnalyzing: Sendable {
    func analyze() -> [CleanupCandidate]
}

struct InstallerArchiveAnalyzer: RecommendationAnalyzing {
    private let roots: [URL]
    private let minimumSize: Int64
    private let minimumAge: TimeInterval
    private let now: @Sendable () -> Date
    private let fileSystem: any FileSystemInspecting

    init(
        roots: [URL] = InstallerArchiveAnalyzer.defaultRoots(),
        minimumSize: Int64 = 10_000_000,
        minimumAge: TimeInterval = 30 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() },
        fileSystem: any FileSystemInspecting = FileSystemInspector()
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.minimumAge = minimumAge
        self.now = now
        self.fileSystem = fileSystem
    }

    func analyze() -> [CleanupCandidate] {
        let extensions: Set<String> = ["dmg", "pkg", "xip", "zip", "ipsw", "iso"]
        let fileManager = FileManager.default
        let cutoff = now().addingTimeInterval(-minimumAge)
        var candidates: [CleanupCandidate] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                enumerator.skipDescendants()
                guard let modifiedAt = fileSystem.modificationDate(of: url), modifiedAt <= cutoff else { continue }
                let size = fileSystem.allocatedSize(of: url)
                guard size >= minimumSize else { continue }
                let ageDays = max(Calendar.current.dateComponents([.day], from: modifiedAt, to: now()).day ?? 0, 0)
                candidates.append(CleanupCandidate(
                    id: "installer:\(url.path)",
                    name: url.lastPathComponent,
                    detail: "Installer or archive last modified \(ageDays) days ago.",
                    path: url.path,
                    category: .installers,
                    safety: .review,
                    strategy: .trashReviewedFile(url),
                    size: size,
                    modifiedAt: modifiedAt
                ))
            }
        }
        return candidates.sorted { $0.size > $1.size }
    }

    static func defaultRoots(fileManager: FileManager = .default) -> [URL] {
        [.downloadsDirectory, .desktopDirectory].flatMap {
            fileManager.urls(for: $0, in: .userDomainMask)
        }
    }
}
