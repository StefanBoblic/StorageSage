//
//  APFSSnapshotAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol APFSSnapshotAnalyzing: Sendable {
    func analyze() -> [APFSSnapshotRecord]
}

struct APFSSnapshotAnalyzer: APFSSnapshotAnalyzing {
    private let commands: any CommandRunning

    init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    func analyze() -> [APFSSnapshotRecord] {
        guard let result = commands.run(
            "diskutil",
            arguments: ["apfs", "listSnapshots", "/", "-plist"],
            timeout: 15
        ), result.terminationStatus == 0,
        let list = try? PropertyListDecoder().decode(SnapshotList.self, from: result.output)
        else { return [] }

        return list.snapshots.map { snapshot in
            APFSSnapshotRecord(
                id: snapshot.uuid,
                name: snapshot.name,
                createdAt: Self.date(from: snapshot.name),
                isPurgeable: snapshot.purgeable,
                limitsContainerShrink: snapshot.limitingContainerShrink
            )
        }.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    private static func date(from name: String) -> Date? {
        let prefix = "com.apple.TimeMachine."
        guard name.hasPrefix(prefix) else { return nil }
        var value = String(name.dropFirst(prefix.count))
        if value.hasSuffix(".local") { value.removeLast(".local".count) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: value)
    }
}

private struct SnapshotList: Decodable {
    let snapshots: [SnapshotPayload]
    enum CodingKeys: String, CodingKey { case snapshots = "Snapshots" }
}

private struct SnapshotPayload: Decodable {
    let name: String
    let uuid: String
    let purgeable: Bool
    let limitingContainerShrink: Bool

    enum CodingKeys: String, CodingKey {
        case name = "SnapshotName"
        case uuid = "SnapshotUUID"
        case purgeable = "Purgeable"
        case limitingContainerShrink = "LimitingContainerShrink"
    }
}
