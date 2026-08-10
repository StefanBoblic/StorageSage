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
    @Published private(set) var isUsingCachedScan = false
    @Published private(set) var isCleaning = false
    @Published private(set) var isPreparingCleanup = false
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var lastReport: CleanupReport?
    @Published private(set) var cleanupProgress: CleanupProgress?
    @Published private(set) var errorMessage: String?
    @Published private(set) var cleanupMeasuredAt: Date?
    @Published private(set) var unavailableSelectionNames: [String] = []

    private let scanner: any StorageScanning
    private let cleaner: any StorageCleaning
    private let scanCache: any ScanResultCaching
    private let preflight: any CleanupPreflightMeasuring
    private var hasScanned = false

    init(
        scanner: any StorageScanning = StorageScanner(),
        cleaner: any StorageCleaning = StorageCleaner(),
        scanCache: any ScanResultCaching = DiskScanResultCache(),
        preflight: any CleanupPreflightMeasuring = CleanupPreflightService()
    ) {
        self.scanner = scanner
        self.cleaner = cleaner
        self.scanCache = scanCache
        self.preflight = preflight
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates.filter { selectedIDs.contains($0.id) && $0.isCleanable }
    }
    var selectedSize: Int64 { selectedCandidates.reduce(0) { $0 + $1.size } }
    var selectedTrashSize: Int64 {
        selectedCandidates.reduce(0) { total, candidate in
            if case .trash = candidate.strategy { return total + candidate.size }
            return total
        }
    }
    var selectedImmediateDeletionSize: Int64 {
        selectedCandidates.reduce(0) { total, candidate in
            candidate.strategy == .deleteUnavailableSimulators ? total + candidate.size : total
        }
    }
    var canModifySelection: Bool { !isScanning && !isUsingCachedScan && !isCleaning && !isPreparingCleanup }
    var canCleanSelection: Bool { canModifySelection && !selectedIDs.isEmpty }
    var cleanableSize: Int64 { candidates.filter(\.isCleanable).reduce(0) { $0 + $1.size } }
    var categoryTotals: [(StorageCategory, Int64)] {
        StorageCategory.allCases.compactMap { category in
            let total = candidates.filter { $0.category == category }.reduce(0) { $0 + $1.size }
            return total > 0 ? (category, total) : nil
        }.sorted { $0.1 > $1.1 }
    }

    func scanIfNeeded() async {
        guard !hasScanned else { return }
        let scanCache = scanCache
        if let cachedResult = await Task.detached(priority: .utility, operation: {
            scanCache.load(maxAge: 24 * 60 * 60)
        }).value {
            apply(cachedResult)
            isUsingCachedScan = true
            hasScanned = true
        }
        await scan()
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let scanner = scanner
        let result = await Task.detached(priority: .userInitiated) { await scanner.scan() }.value
        apply(result)
        isUsingCachedScan = false
        let scanCache = scanCache
        await Task.detached(priority: .utility) { scanCache.save(result) }.value
        hasScanned = true
        isScanning = false
    }

    private func apply(_ result: ScanResult) {
        candidates = result.candidates
        volume = result.volume
        inaccessiblePaths = result.inaccessiblePaths
        scannedAt = result.scannedAt
        selectedIDs = selectedIDs.intersection(Set(candidates.filter(\.isCleanable).map(\.id)))
    }

    func toggle(_ candidate: CleanupCandidate) {
        guard candidate.isCleanable, canModifySelection else { return }
        resetCleanupFeedback()
        if selectedIDs.contains(candidate.id) { selectedIDs.remove(candidate.id) }
        else { selectedIDs.insert(candidate.id) }
    }

    func selectSafeItems() {
        guard canModifySelection else { return }
        resetCleanupFeedback()
        selectedIDs = Set(candidates.filter { $0.isCleanable && $0.safety == .safe }.map(\.id))
    }

    func clearSelection() {
        guard canModifySelection else { return }
        resetCleanupFeedback()
        selectedIDs.removeAll()
    }

    func reveal(_ candidate: CleanupCandidate) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: candidate.path)])
    }

    @discardableResult
    func prepareSelectedCleanup() async -> Bool {
        let selection = selectedCandidates
        guard !selection.isEmpty, canCleanSelection else { return false }
        isPreparingCleanup = true
        cleanupMeasuredAt = nil
        unavailableSelectionNames = []
        let preflight = preflight
        let preparation = await Task.detached(priority: .userInitiated) {
            preflight.measure(selection)
        }.value

        let measuredByID = Dictionary(uniqueKeysWithValues: preparation.candidates.map { ($0.id, $0) })
        candidates = candidates.map { measuredByID[$0.id] ?? $0 }
        selectedIDs = Set(preparation.candidates.map(\.id))
        unavailableSelectionNames = preparation.unavailableNames
        cleanupMeasuredAt = preparation.measuredAt
        isPreparingCleanup = false
        return !selectedIDs.isEmpty
    }

    func cleanSelected() async {
        let selection = selectedCandidates
        guard !selection.isEmpty, canCleanSelection else { return }
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
        if report.removedCount > 0 {
            await scan()
        }
        isCleaning = false
    }

    private func resetCleanupFeedback() {
        cleanupProgress = nil
        lastReport = nil
        cleanupMeasuredAt = nil
        unavailableSelectionNames = []
    }

}
