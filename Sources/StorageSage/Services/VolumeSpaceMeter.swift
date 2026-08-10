//
//  VolumeSpaceMeter.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol VolumeSpaceMeasuring: Sendable {
    func availableBytes() -> Int64?
}

struct VolumeSpaceMeter: VolumeSpaceMeasuring {
    private let volumeURL: URL

    init(volumeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.volumeURL = volumeURL
    }

    func availableBytes() -> Int64? {
        guard let values = try? volumeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else { return nil }
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return values.volumeAvailableCapacity.map(Int64.init)
    }
}
