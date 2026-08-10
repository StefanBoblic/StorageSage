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

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .cleanup: return "sparkles"
        case .applications: return "square.grid.2x2.fill"
        }
    }
}

enum StorageCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case simulators = "Simulators"
    case xcode = "Xcode"
    case caches = "Caches"
    case developer = "Developer Tools"
    case appData = "App Data"
    case applications = "Applications"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .simulators: return "iphone.gen3"
        case .xcode: return "hammer.fill"
        case .caches: return "shippingbox.fill"
        case .developer: return "terminal.fill"
        case .appData: return "externaldrive.fill"
        case .applications: return "app.fill"
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

    var removedCount: Int { movedToTrashCount + deletedImmediatelyCount }
    var handledBytes: Int64 { movedToTrashBytes + deletedImmediatelyBytes }
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
