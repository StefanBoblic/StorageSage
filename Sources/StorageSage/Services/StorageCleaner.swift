//
//  StorageCleaner.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol StorageCleaning: Sendable {
    func clean(_ candidates: [CleanupCandidate]) -> CleanupReport
}

struct StorageCleaner: StorageCleaning {
    private let policy: any DeletionPolicyEvaluating
    private let configuration: any CleanupConfigurationProviding
    private let processGuard: any CleanupProcessGuarding
    private let commands: any CommandRunning

    init(
        policy: any DeletionPolicyEvaluating = DefaultDeletionPolicy(),
        configuration: any CleanupConfigurationProviding = UserDefaultsCleanupConfiguration(),
        processGuard: any CleanupProcessGuarding = CleanupProcessGuard(),
        commands: any CommandRunning = CommandRunner()
    ) {
        self.policy = policy
        self.configuration = configuration
        self.processGuard = processGuard
        self.commands = commands
    }

    func clean(_ candidates: [CleanupCandidate]) -> CleanupReport {
        var report = CleanupReport(isDryRun: configuration.isDryRunEnabled)

        for candidate in candidates {
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
                continue
            }

            do {
                if try execute(candidate) {
                    report.reclaimed += candidate.size
                    report.removedCount += 1
                }
            } catch {
                report.errors.append("\(candidate.name): \(error.localizedDescription)")
            }
        }

        return report
    }

    private func execute(_ candidate: CleanupCandidate) throws -> Bool {
        switch candidate.strategy {
        case .trash(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return true
        case .deleteUnavailableSimulators:
            try deleteUnavailableSimulators()
            return true
        case .none:
            return false
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
