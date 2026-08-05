//
//  CleanupConfiguration.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol CleanupConfigurationProviding: Sendable {
    var isDryRunEnabled: Bool { get }
}

struct UserDefaultsCleanupConfiguration: CleanupConfigurationProviding {
    var isDryRunEnabled: Bool {
        UserDefaults.standard.bool(forKey: StoragePreferenceKeys.dryRun)
    }
}
