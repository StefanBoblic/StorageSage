//
//  ProjectArtifactAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol ProjectRootLocating: Sendable {
    func projectRoots() -> [URL]
}

struct SpotlightProjectRootLocator: ProjectRootLocating {
    private let commands: any CommandRunning
    private let searchRoot: URL

    init(
        commands: any CommandRunning = CommandRunner(),
        searchRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.commands = commands
        self.searchRoot = searchRoot
    }

    func projectRoots() -> [URL] {
        let names = ["Package.swift", "package.json", "Podfile", "build.gradle", "settings.gradle", "pyproject.toml"]
        let query = names.map { "kMDItemFSName == '\($0)'" }.joined(separator: " || ")
        guard let result = commands.run(
            "mdfind",
            arguments: ["-0", "-onlyin", searchRoot.path, query],
            timeout: 20
        ), result.terminationStatus == 0 else { return [] }
        return Array(Set(result.output.split(separator: 0).compactMap { bytes -> URL? in
            guard let path = String(data: Data(bytes), encoding: .utf8) else { return nil }
            return URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
        })).sorted { $0.path < $1.path }
    }
}

struct ProjectArtifactAnalyzer: RecommendationAnalyzing {
    private let roots: any ProjectRootLocating
    private let fileSystem: any FileSystemInspecting
    private let minimumSize: Int64
    private let exclusions: any ScanExclusionProviding

    init(
        roots: any ProjectRootLocating = SpotlightProjectRootLocator(),
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        minimumSize: Int64 = 10_000_000,
        exclusions: any ScanExclusionProviding = UserDefaultsScanExclusionStore()
    ) {
        self.roots = roots
        self.fileSystem = fileSystem
        self.minimumSize = minimumSize
        self.exclusions = exclusions
    }

    func analyze() -> [CleanupCandidate] {
        let fileManager = FileManager.default
        var candidatesByPath: [String: CleanupCandidate] = [:]

        for projectRoot in roots.projectRoots() where !exclusions.excludes(projectRoot) {
            let markerNames = Set((try? fileManager.contentsOfDirectory(atPath: projectRoot.path)) ?? [])
            let artifactNames = artifactNames(for: markerNames)
            for name in artifactNames {
                let artifactURL = projectRoot.appendingPathComponent(name, isDirectory: true)
                guard fileSystem.exists(artifactURL), !exclusions.excludes(artifactURL) else { continue }
                let size = fileSystem.allocatedSize(of: artifactURL)
                guard size >= minimumSize else { continue }
                candidatesByPath[artifactURL.standardizedFileURL.path] = CleanupCandidate(
                    id: "project-artifact:\(artifactURL.standardizedFileURL.path)",
                    name: "\(projectRoot.lastPathComponent) / \(name)",
                    detail: "Rebuildable output detected from project markers.",
                    path: artifactURL.standardizedFileURL.path,
                    category: .projectArtifacts,
                    safety: .review,
                    strategy: .trashReviewedDirectory(artifactURL.standardizedFileURL),
                    size: size,
                    modifiedAt: fileSystem.modificationDate(of: artifactURL)
                )
            }
        }
        return candidatesByPath.values.sorted { $0.size > $1.size }
    }

    private func artifactNames(for markers: Set<String>) -> Set<String> {
        var names: Set<String> = []
        if markers.contains("package.json") { names.insert("node_modules") }
        if markers.contains("Package.swift") { names.insert(".build") }
        if markers.contains("Podfile") { names.insert("Pods") }
        if markers.contains("build.gradle") || markers.contains("settings.gradle") {
            names.formUnion(["build", ".gradle"])
        }
        if markers.contains("pyproject.toml") {
            names.formUnion([".venv", "venv"])
        }
        return names
    }
}
