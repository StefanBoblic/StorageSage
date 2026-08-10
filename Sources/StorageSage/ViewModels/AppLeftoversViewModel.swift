//
//  AppLeftoversViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import AppKit
import Foundation

@MainActor
final class AppLeftoversViewModel: ObservableObject {
    @Published private(set) var records: [AppLeftoverRecord] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isCleaning = false
    @Published private(set) var lastReport: CleanupReport?

    private let analyzer: any AppLeftoverAnalyzing
    private let preflight: any CleanupPreflightMeasuring
    private let cleaner: any StorageCleaning

    init(
        analyzer: any AppLeftoverAnalyzing = AppLeftoverAnalyzer(),
        preflight: any CleanupPreflightMeasuring = CleanupPreflightService(),
        cleaner: any StorageCleaning = StorageCleaner()
    ) {
        self.analyzer = analyzer
        self.preflight = preflight
        self.cleaner = cleaner
    }

    var selectedRecords: [AppLeftoverRecord] { records.filter { selectedIDs.contains($0.id) } }
    var selectedSize: Int64 { selectedRecords.reduce(0) { $0 + $1.size } }
    var canModifySelection: Bool { !isScanning && !isPreparing && !isCleaning }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        selectedIDs.removeAll()
        let analyzer = analyzer
        records = await Task.detached(priority: .utility) { analyzer.analyze() }.value
        isScanning = false
    }

    func toggle(_ record: AppLeftoverRecord) {
        guard canModifySelection else { return }
        lastReport = nil
        if selectedIDs.contains(record.id) { selectedIDs.remove(record.id) }
        else { selectedIDs.insert(record.id) }
    }

    @discardableResult
    func prepareSelection() async -> Bool {
        let selection = selectedRecords
        guard !selection.isEmpty, canModifySelection else { return false }
        isPreparing = true
        let preflight = preflight
        let preparation = await Task.detached(priority: .userInitiated) {
            preflight.measure(selection.map(\.cleanupCandidate))
        }.value
        let measuredByID = Dictionary(uniqueKeysWithValues: preparation.candidates.map { ($0.id, $0) })
        records = records.compactMap { record in
            guard selectedIDs.contains(record.id) else { return record }
            guard let candidate = measuredByID[record.id] else { return nil }
            return AppLeftoverRecord(
                url: record.url,
                bundleIdentifier: record.bundleIdentifier,
                locationName: record.locationName,
                size: candidate.size,
                modifiedAt: candidate.modifiedAt
            )
        }
        selectedIDs.formIntersection(Set(preparation.candidates.map(\.id)))
        isPreparing = false
        return !selectedIDs.isEmpty
    }

    func cleanSelected() async {
        let selection = selectedRecords.map(\.cleanupCandidate)
        guard !selection.isEmpty, canModifySelection else { return }
        isCleaning = true
        let cleaner = cleaner
        lastReport = await Task.detached(priority: .userInitiated) {
            cleaner.clean(selection) { _ in }
        }.value
        selectedIDs.removeAll()
        if lastReport?.removedCount ?? 0 > 0 {
            await scan()
        }
        isCleaning = false
    }

    func reveal(_ record: AppLeftoverRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.url])
    }
}
