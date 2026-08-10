//
//  StorageModels.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation
import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case cleanup = "Cleanup"
    case applications = "Applications"
    case largeFiles = "Large Files"
    case leftovers = "App Leftovers"
    case duplicates = "Duplicates"
    case recommendations = "Recommendations"
    case growth = "Growth Monitor"
    case snapshots = "APFS Snapshots"
    case history = "Cleanup History"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .cleanup: return "sparkles"
        case .applications: return "square.grid.2x2.fill"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .leftovers: return "shippingbox.and.arrow.backward.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .recommendations: return "lightbulb.fill"
        case .growth: return "chart.line.uptrend.xyaxis"
        case .snapshots: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .history: return "clock.fill"
        }
    }
}

struct LargeFileRecord: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modifiedAt: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct AppLeftoverRecord: Identifiable, Hashable, Sendable {
    let url: URL
    let bundleIdentifier: String
    let locationName: String
    let size: Int64
    let modifiedAt: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var cleanupCandidate: CleanupCandidate {
        CleanupCandidate(
            id: id,
            name: name,
            detail: "Possible leftover from \(bundleIdentifier) in \(locationName).",
            path: url.path,
            category: .appData,
            safety: .review,
            strategy: .trash(url),
            size: size,
            modifiedAt: modifiedAt
        )
    }
}

struct DuplicateFileRecord: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modifiedAt: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let fingerprint: String
    let files: [DuplicateFileRecord]

    var id: String { fingerprint }
    var fileSize: Int64 { files.first?.size ?? 0 }
    var reclaimableSize: Int64 { fileSize * Int64(max(files.count - 1, 0)) }
}

struct APFSSnapshotRecord: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date?
    let isPurgeable: Bool
    let limitsContainerShrink: Bool

    var kind: String {
        if name.hasPrefix("com.apple.TimeMachine") { return "Time Machine" }
        if name.hasPrefix("com.apple.os.update") { return "macOS Update" }
        return "APFS"
    }
}

struct CleanupHistoryItem: Identifiable, Codable, Hashable, Sendable {
    let path: String
    let name: String
    let estimatedBytes: Int64
    var id: String { path }
}

struct CleanupHistoryRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let source: String
    let items: [CleanupHistoryItem]
    let movedToTrashBytes: Int64
    let deletedImmediatelyBytes: Int64
    let actualFreedBytes: Int64?
    let isDryRun: Bool
    let errorCount: Int
    let skippedCount: Int
}

enum StorageCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case simulators = "Simulators"
    case xcode = "Xcode"
    case caches = "Caches"
    case developer = "Developer Tools"
    case appData = "App Data"
    case applications = "Applications"
    case installers = "Installers & Archives"
    case projectArtifacts = "Project Artifacts"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .simulators: return "iphone.gen3"
        case .xcode: return "hammer.fill"
        case .caches: return "shippingbox.fill"
        case .developer: return "terminal.fill"
        case .appData: return "externaldrive.fill"
        case .applications: return "app.fill"
        case .installers: return "shippingbox.fill"
        case .projectArtifacts: return "hammer.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .simulators: return .blue
        case .xcode: return .indigo
        case .caches: return .orange
        case .developer: return .purple
        case .appData: return .teal
        case .applications: return .pink
        case .installers: return .mint
        case .projectArtifacts: return .cyan
        }
    }
}

enum SafetyLevel: String, Codable, Sendable {
    case safe = "Safe to Remove"
    case review = "Review First"
    case analysisOnly = "Analysis Only"

    var color: Color {
        switch self {
        case .safe: return .green
        case .review: return .orange
        case .analysisOnly: return .secondary
        }
    }
    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .review: return "exclamationmark.triangle.fill"
        case .analysisOnly: return "eye.fill"
        }
    }
}

enum CleanupStrategy: Hashable, Sendable {
    case trash(URL)
    case trashReviewedFile(URL)
    case trashReviewedDirectory(URL)
    case deleteUnavailableSimulators
    case none
}

struct CleanupCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let path: String
    let category: StorageCategory
    let safety: SafetyLevel
    let strategy: CleanupStrategy
    let size: Int64
    let modifiedAt: Date?

    var isCleanable: Bool { strategy != .none }

    func replacing(size: Int64, modifiedAt: Date?) -> CleanupCandidate {
        CleanupCandidate(
            id: id,
            name: name,
            detail: detail,
            path: path,
            category: category,
            safety: safety,
            strategy: strategy,
            size: size,
            modifiedAt: modifiedAt
        )
    }
}

struct CleanupPreparation: Sendable {
    let candidates: [CleanupCandidate]
    let unavailableNames: [String]
    let measuredAt: Date
}

struct VolumeSnapshot: Sendable {
    var total: Int64 = 0
    var available: Int64 = 0
    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct ScanResult: Sendable {
    var candidates: [CleanupCandidate]
    var volume: VolumeSnapshot
    var inaccessiblePaths: [String]
    var scannedAt: Date
}

struct CleanupReport {
    var movedToTrashBytes: Int64 = 0
    var deletedImmediatelyBytes: Int64 = 0
    var movedToTrashCount: Int = 0
    var deletedImmediatelyCount: Int = 0
    var previewedCount: Int = 0
    var estimatedReclaimable: Int64 = 0
    var estimatedTrashBytes: Int64 = 0
    var estimatedImmediateDeletionBytes: Int64 = 0
    var skipped: [String] = []
    var errors: [String] = []
    var isDryRun = false
    var availableBytesBefore: Int64?
    var availableBytesAfter: Int64?

    var removedCount: Int { movedToTrashCount + deletedImmediatelyCount }
    var handledBytes: Int64 { movedToTrashBytes + deletedImmediatelyBytes }
    var actualFreedBytes: Int64? {
        guard let availableBytesBefore, let availableBytesAfter else { return nil }
        return max(availableBytesAfter - availableBytesBefore, 0)
    }
}

struct CleanupProgress: Equatable, Sendable {
    let totalBytes: Int64
    let totalCount: Int
    let isDryRun: Bool
    var processedBytes: Int64 = 0
    var eligibleBytes: Int64 = 0
    var movedToTrashBytes: Int64 = 0
    var deletedImmediatelyBytes: Int64 = 0
    var processedCount: Int = 0

    var fractionCompleted: Double {
        if totalBytes > 0 {
            return min(Double(processedBytes) / Double(totalBytes), 1)
        }
        return totalCount > 0 ? min(Double(processedCount) / Double(totalCount), 1) : 0
    }

    var displayedBytes: Int64 {
        isDryRun ? eligibleBytes : movedToTrashBytes + deletedImmediatelyBytes
    }
}

extension Int64 {
    var fileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
