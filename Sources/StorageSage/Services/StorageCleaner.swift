//
//  StorageCleaner.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol StorageCleaning: Sendable {
    func clean(
        _ candidates: [CleanupCandidate],
        progress: @escaping @Sendable (CleanupProgress) -> Void
    ) -> CleanupReport
}

struct StorageCleaner: StorageCleaning {
    private let policy: any DeletionPolicyEvaluating
    private let configuration: any CleanupConfigurationProviding
    private let processGuard: any CleanupProcessGuarding
    private let commands: any CommandRunning
    private let volumeSpace: any VolumeSpaceMeasuring

    init(
        policy: any DeletionPolicyEvaluating = DefaultDeletionPolicy(),
        configuration: any CleanupConfigurationProviding = UserDefaultsCleanupConfiguration(),
        processGuard: any CleanupProcessGuarding = CleanupProcessGuard(),
        commands: any CommandRunning = CommandRunner(),
        volumeSpace: any VolumeSpaceMeasuring = VolumeSpaceMeter()
    ) {
        self.policy = policy
        self.configuration = configuration
        self.processGuard = processGuard
        self.commands = commands
        self.volumeSpace = volumeSpace
    }

    func clean(
        _ candidates: [CleanupCandidate],
        progress progressHandler: @escaping @Sendable (CleanupProgress) -> Void = { _ in }
    ) -> CleanupReport {
        var report = CleanupReport(isDryRun: configuration.isDryRunEnabled)
        if !report.isDryRun {
            report.availableBytesBefore = volumeSpace.availableBytes()
        }
        var cleanupProgress = CleanupProgress(
            totalBytes: candidates.reduce(0) { $0 + $1.size },
            totalCount: candidates.count,
            isDryRun: report.isDryRun
        )
        progressHandler(cleanupProgress)

        for candidate in candidates {
            defer {
                cleanupProgress.processedBytes += candidate.size
                cleanupProgress.processedCount += 1
                progressHandler(cleanupProgress)
            }

            let decision = policy.evaluate(candidate)
            guard case .allowed = decision else {
                if case .denied(let reason) = decision {
                    report.skipped.append("\(candidate.name): \(reason)")
                }
                continue
            }
            if let reason = processGuard.blockingReason(for: candidate) {
                report.skipped.append("\(candidate.name): \(reason)")
                continue
            }
            if report.isDryRun {
                report.previewedCount += 1
                report.estimatedReclaimable += candidate.size
                cleanupProgress.eligibleBytes += candidate.size
                switch candidate.strategy {
                case .trash, .trashReviewedFile:
                    report.estimatedTrashBytes += candidate.size
                case .deleteUnavailableSimulators:
                    report.estimatedImmediateDeletionBytes += candidate.size
                case .none:
                    break
                }
                continue
            }

            do {
                switch try execute(candidate) {
                case .movedToTrash:
                    report.movedToTrashBytes += candidate.size
                    report.movedToTrashCount += 1
                    cleanupProgress.movedToTrashBytes += candidate.size
                case .deletedImmediately:
                    report.deletedImmediatelyBytes += candidate.size
                    report.deletedImmediatelyCount += 1
                    cleanupProgress.deletedImmediatelyBytes += candidate.size
                case .noChange:
                    break
                }
            } catch {
                report.errors.append("\(candidate.name): \(error.localizedDescription)")
            }
        }

        if !report.isDryRun {
            report.availableBytesAfter = volumeSpace.availableBytes()
        }
        return report
    }

    private func execute(_ candidate: CleanupCandidate) throws -> CleanupOutcome {
        switch candidate.strategy {
        case .trash(let url), .trashReviewedFile(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return .noChange }
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return .movedToTrash
        case .deleteUnavailableSimulators:
            try deleteUnavailableSimulators()
            return .deletedImmediately
        case .none:
            return .noChange
        }
    }

    private func deleteUnavailableSimulators() throws {
        guard let result = commands.run(
            "xcrun",
            arguments: ["simctl", "delete", "unavailable"],
            timeout: 60
        ) else {
            throw cleanupError("xcrun could not be run.")
        }
        guard result.terminationStatus == 0 else {
            let message = String(data: result.errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw cleanupError(message?.isEmpty == false ? message! : "simctl returned an error.")
        }
    }

    private func cleanupError(_ message: String) -> NSError {
        NSError(
            domain: "StorageSage",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private enum CleanupOutcome {
    case movedToTrash
    case deletedImmediately
    case noChange
}
