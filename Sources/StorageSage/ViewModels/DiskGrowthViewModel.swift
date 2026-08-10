//
//  DiskGrowthViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import AppKit
import Foundation

@MainActor
final class DiskGrowthViewModel: ObservableObject {
    @Published private(set) var history: [DiskGrowthSnapshot] = []
    @Published private(set) var isMeasuring = false
    @Published private(set) var isStale = false
    @Published private(set) var errorMessage: String?
    @Published var selectedRange: GrowthHistoryRange = .week

    private let analyzer: any DiskGrowthAnalyzing
    private let store: any DiskGrowthStoring
    private let defaults: UserDefaults
    private var hasLoaded = false

    init(
        analyzer: any DiskGrowthAnalyzing = DiskGrowthAnalyzer(),
        store: any DiskGrowthStoring = DiskGrowthStore(),
        defaults: UserDefaults = .standard
    ) {
        self.analyzer = analyzer
        self.store = store
        self.defaults = defaults
    }

    var latestSnapshot: DiskGrowthSnapshot? { history.last }
    var hasBaseline: Bool { !history.isEmpty }
    var automaticTrackingEnabled: Bool {
        defaults.object(forKey: StoragePreferenceKeys.automaticGrowthTracking) as? Bool ?? true
    }
    var comparison: DiskGrowthComparison? {
        guard let current = latestSnapshot, let baseline = selectedBaseline(for: current) else { return nil }
        return DiskGrowthComparison(baseline: baseline, current: current)
    }
    var visibleHistory: [DiskGrowthSnapshot] {
        guard let latest = latestSnapshot, let baseline = selectedBaseline(for: latest) else { return history }
        return history.filter { $0.volumeID == latest.volumeID && $0.createdAt >= baseline.createdAt }
    }

    func load() async {
        guard !hasLoaded else { return }
        history = await store.load()
        hasLoaded = true
        guard automaticTrackingEnabled else { return }
        if let latestSnapshot {
            if Date().timeIntervalSince(latestSnapshot.createdAt) >= 6 * 60 * 60 {
                await refresh(trigger: .applicationLaunch, affectedPaths: nil, automatic: true)
            }
        }
    }

    func establishBaseline() async {
        await refresh(trigger: .baseline, affectedPaths: nil, automatic: false)
        selectedRange = .baseline
    }

    func refresh(
        trigger: GrowthSnapshotTrigger = .manual,
        affectedPaths: [String]? = nil,
        automatic: Bool = false
    ) async {
        guard !isMeasuring, !automatic || automaticTrackingEnabled else { return }
        isMeasuring = true
        errorMessage = nil
        let snapshot = await analyzer.createSnapshot(
            previous: latestSnapshot,
            affectedPaths: affectedPaths,
            trigger: trigger
        )
        history = await store.append(snapshot)
        isStale = false
        isMeasuring = false
    }

    func noteFileChanges(_ batch: FileChangeBatch) {
        guard hasBaseline else { return }
        isStale = true
        guard automaticTrackingEnabled, shouldRunAutomaticRefresh else { return }
        Task {
            await refresh(
                trigger: .filesystemChange,
                affectedPaths: batch.requiresFullRescan ? nil : batch.paths,
                automatic: true
            )
        }
    }

    func noteOverviewScan() {
        guard hasBaseline, automaticTrackingEnabled, shouldRunAutomaticRefresh else { return }
        Task { await refresh(trigger: .overviewScan, affectedPaths: nil, automatic: true) }
    }

    func clearHistory() async {
        await store.clear()
        history = []
        isStale = false
    }

    func reveal(_ change: GrowthBucketChange) {
        guard let path = change.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private var shouldRunAutomaticRefresh: Bool {
        guard let latestSnapshot else { return true }
        return Date().timeIntervalSince(latestSnapshot.createdAt) >= 15 * 60
    }

    private func selectedBaseline(for current: DiskGrowthSnapshot) -> DiskGrowthSnapshot? {
        let compatible = history.filter { $0.volumeID == current.volumeID && $0.id != current.id }
        guard !compatible.isEmpty else { return nil }
        switch selectedRange {
        case .lastSnapshot:
            return compatible.last
        case .baseline:
            return compatible.last(where: { $0.trigger == .baseline }) ?? compatible.first
        case .all:
            return compatible.first
        case .day, .week, .month:
            guard let interval = selectedRange.interval else { return compatible.first }
            let target = current.createdAt.addingTimeInterval(-interval)
            return compatible.last(where: { $0.createdAt <= target }) ?? compatible.first
        }
    }
}
