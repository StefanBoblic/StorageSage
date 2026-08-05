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

struct CleanupCandidate: Identifiable, Hashable {
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
}

struct VolumeSnapshot {
    var total: Int64 = 0
    var available: Int64 = 0
    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct ScanResult {
    var candidates: [CleanupCandidate]
    var volume: VolumeSnapshot
    var inaccessiblePaths: [String]
    var scannedAt: Date
}

struct CleanupReport {
    var reclaimed: Int64 = 0
    var removedCount: Int = 0
    var errors: [String] = []
}

extension Int64 {
    var fileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
