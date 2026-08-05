//
//  ScanConfiguration.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

enum StoragePreferenceKeys {
    static let dryRun = "cleanup.dryRun"
    static let whitelist = "cleanup.whitelist"
    static let maximumConcurrentScans = "scanner.maximumConcurrentTasks"
}

protocol ScanConfigurationProviding: Sendable {
    var maximumConcurrentTasks: Int { get }
}

struct UserDefaultsScanConfiguration: ScanConfigurationProviding {
    static var recommendedConcurrency: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2), 6)
    }

    var maximumConcurrentTasks: Int {
        let stored = UserDefaults.standard.integer(forKey: StoragePreferenceKeys.maximumConcurrentScans)
        return min(max(stored == 0 ? Self.recommendedConcurrency : stored, 1), 8)
    }
}
