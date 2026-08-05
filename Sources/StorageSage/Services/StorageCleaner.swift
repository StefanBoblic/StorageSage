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
    func clean(_ candidates: [CleanupCandidate]) -> CleanupReport {
        var report = CleanupReport()

        for candidate in candidates {
            do {
                switch candidate.strategy {
                case .trash(let url):
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                case .deleteUnavailableSimulators:
                    try deleteUnavailableSimulators()
                case .none:
                    continue
                }
                report.reclaimed += candidate.size
                report.removedCount += 1
            } catch {
                report.errors.append("\(candidate.name): \(error.localizedDescription)")
            }
        }

        return report
    }

    private func deleteUnavailableSimulators() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "delete", "unavailable"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "simctl returned an error."
            throw NSError(
                domain: "StorageSage",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
