//
//  CleanupPreflightService.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol CleanupPreflightMeasuring: Sendable {
    func measure(_ candidates: [CleanupCandidate]) -> CleanupPreparation
}

struct CleanupPreflightService: CleanupPreflightMeasuring {
    private let fileSystem: any FileSystemInspecting
    private let simulatorAnalyzer: any StorageAnalyzing

    init(
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        simulatorAnalyzer: any StorageAnalyzing = SimulatorStorageAnalyzer()
    ) {
        self.fileSystem = fileSystem
        self.simulatorAnalyzer = simulatorAnalyzer
    }

    func measure(_ candidates: [CleanupCandidate]) -> CleanupPreparation {
        let currentSimulatorCandidate = candidates.contains { $0.strategy == .deleteUnavailableSimulators }
            ? simulatorAnalyzer.analyze().first { $0.strategy == .deleteUnavailableSimulators }
            : nil
        var measured: [CleanupCandidate] = []
        var unavailableNames: [String] = []

        for candidate in candidates {
            switch candidate.strategy {
            case .trash(let url), .trashReviewedFile(let url), .trashReviewedDirectory(let url):
                guard fileSystem.exists(url) else {
                    unavailableNames.append(candidate.name)
                    continue
                }
                guard fileSystem.canMoveToTrash(url) else {
                    unavailableNames.append(candidate.name)
                    continue
                }
                measured.append(candidate.replacing(
                    size: fileSystem.allocatedSize(of: url),
                    modifiedAt: fileSystem.modificationDate(of: url)
                ))
            case .deleteUnavailableSimulators:
                if let currentSimulatorCandidate {
                    measured.append(currentSimulatorCandidate)
                } else {
                    unavailableNames.append(candidate.name)
                }
            case .none:
                unavailableNames.append(candidate.name)
            }
        }

        return CleanupPreparation(
            candidates: measured,
            unavailableNames: unavailableNames,
            measuredAt: Date()
        )
    }
}
