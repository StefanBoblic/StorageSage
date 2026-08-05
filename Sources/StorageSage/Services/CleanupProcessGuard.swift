//
//  CleanupProcessGuard.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol CleanupProcessGuarding: Sendable {
    func blockingReason(for candidate: CleanupCandidate) -> String?
}

struct CleanupProcessGuard: CleanupProcessGuarding {
    private let commands: any CommandRunning

    init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    func blockingReason(for candidate: CleanupCandidate) -> String? {
        if candidate.category == .xcode, isProcessRunning("Xcode") {
            return "Quit Xcode before cleaning its generated data."
        }
        if candidate.strategy == .deleteUnavailableSimulators, hasBootedSimulator() {
            return "Shut down all Simulator devices before removing unavailable devices."
        }
        return nil
    }

    private func isProcessRunning(_ name: String) -> Bool {
        commands.run("pgrep", arguments: ["-x", name], timeout: 2)?.terminationStatus == 0
    }

    private func hasBootedSimulator() -> Bool {
        guard
            let result = commands.run(
                "xcrun",
                arguments: ["simctl", "list", "devices", "booted", "--json"],
                timeout: 5
            ),
            result.terminationStatus == 0,
            let object = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any],
            let devices = object["devices"] as? [String: [[String: Any]]]
        else { return false }
        return devices.values.contains { !$0.isEmpty }
    }
}
