//
//  StorageViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation
import SwiftUI

@MainActor
final class StorageViewModel: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var volume = VolumeSnapshot()
    @Published private(set) var inaccessiblePaths: [String] = []
    @Published private(set) var scannedAt: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var lastReport: CleanupReport?
    @Published private(set) var cleanupProgress: CleanupProgress?
    @Published private(set) var errorMessage: String?

    private let scanner: any StorageScanning
    private let cleaner: any StorageCleaning
    private var hasScanned = false

    init(
        scanner: any StorageScanning = StorageScanner(),
        cleaner: any StorageCleaning = StorageCleaner()
    ) {
        self.scanner = scanner
        self.cleaner = cleaner
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates.filter { selectedIDs.contains($0.id) && $0.isCleanable }
    }
    var selectedSize: Int64 { selectedCandidates.reduce(0) { $0 + $1.size } }
    var cleanableSize: Int64 { candidates.filter(\.isCleanable).reduce(0) { $0 + $1.size } }
    var categoryTotals: [(StorageCategory, Int64)] {
        StorageCategory.allCases.compactMap { category in
            let total = candidates.filter { $0.category == category }.reduce(0) { $0 + $1.size }
            return total > 0 ? (category, total) : nil
        }.sorted { $0.1 > $1.1 }
    }

    func scanIfNeeded() async {
        guard !hasScanned else { return }
        await scan()
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let scanner = scanner
        let result = await Task.detached(priority: .userInitiated) { await scanner.scan() }.value
        candidates = result.candidates
        volume = result.volume
        inaccessiblePaths = result.inaccessiblePaths
        scannedAt = result.scannedAt
        selectedIDs = selectedIDs.intersection(Set(candidates.filter(\.isCleanable).map(\.id)))
        hasScanned = true
        isScanning = false
    }

    func toggle(_ candidate: CleanupCandidate) {
        guard candidate.isCleanable else { return }
        if selectedIDs.contains(candidate.id) { selectedIDs.remove(candidate.id) }
        else { selectedIDs.insert(candidate.id) }
    }

    func selectSafeItems() {
        selectedIDs = Set(candidates.filter { $0.isCleanable && $0.safety == .safe }.map(\.id))
    }

    func clearSelection() { selectedIDs.removeAll() }

    func reveal(_ candidate: CleanupCandidate) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: candidate.path)])
    }

    func cleanSelected() async {
        let selection = selectedCandidates
        guard !selection.isEmpty else { return }
        isCleaning = true
        let cleaner = cleaner
        let (progressStream, progressContinuation) = AsyncStream<CleanupProgress>.makeStream()
        let progressTask = Task { [weak self] in
            for await progress in progressStream {
                self?.cleanupProgress = progress
            }
        }
        let report = await Task.detached(priority: .userInitiated) {
            cleaner.clean(selection) { progress in
                progressContinuation.yield(progress)
            }
        }.value
        progressContinuation.finish()
        await progressTask.value

        lastReport = report
        selectedIDs.removeAll()
        isCleaning = false
        await scan()
    }

}
