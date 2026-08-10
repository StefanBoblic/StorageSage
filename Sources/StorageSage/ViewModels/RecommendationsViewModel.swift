//
//  RecommendationsViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

@MainActor
final class RecommendationsViewModel: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isCleaning = false
    @Published private(set) var isStale = false
    @Published private(set) var lastReport: CleanupReport?

    private let analyzers: [any RecommendationAnalyzing]
    private let preflight: any CleanupPreflightMeasuring
    private let cleaner: any StorageCleaning

    init(
        analyzers: [any RecommendationAnalyzing] = [InstallerArchiveAnalyzer(), ProjectArtifactAnalyzer()],
        preflight: any CleanupPreflightMeasuring = CleanupPreflightService(),
        cleaner: any StorageCleaning = StorageCleaner()
    ) {
        self.analyzers = analyzers
        self.preflight = preflight
        self.cleaner = cleaner
    }

    var selectedCandidates: [CleanupCandidate] { candidates.filter { selectedIDs.contains($0.id) } }
    var selectedSize: Int64 { selectedCandidates.reduce(0) { $0 + $1.size } }
    var canModifySelection: Bool { !isScanning && !isPreparing && !isCleaning }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        selectedIDs.removeAll()
        candidates = await withTaskGroup(of: [CleanupCandidate].self, returning: [CleanupCandidate].self) { group in
            for analyzer in analyzers { group.addTask { analyzer.analyze() } }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }.sorted { $0.size > $1.size }
        isStale = false
        isScanning = false
    }

    func toggle(_ candidate: CleanupCandidate) {
        guard canModifySelection else { return }
        lastReport = nil
        if selectedIDs.contains(candidate.id) { selectedIDs.remove(candidate.id) }
        else { selectedIDs.insert(candidate.id) }
    }

    @discardableResult
    func prepareSelection() async -> Bool {
        let selection = selectedCandidates
        guard !selection.isEmpty, canModifySelection else { return false }
        isPreparing = true
        let preflight = preflight
        let preparation = await Task.detached(priority: .userInitiated) {
            preflight.measure(selection)
        }.value
        let measured = Dictionary(uniqueKeysWithValues: preparation.candidates.map { ($0.id, $0) })
        candidates = candidates.compactMap { selectedIDs.contains($0.id) ? measured[$0.id] : $0 }
        selectedIDs.formIntersection(Set(preparation.candidates.map(\.id)))
        isPreparing = false
        return !selectedIDs.isEmpty
    }

    func cleanSelected() async {
        let selection = selectedCandidates
        guard !selection.isEmpty, canModifySelection else { return }
        isCleaning = true
        let cleaner = cleaner
        lastReport = await Task.detached(priority: .userInitiated) {
            cleaner.clean(selection) { _ in }
        }.value
        selectedIDs.removeAll()
        if lastReport?.removedCount ?? 0 > 0 { await scan() }
        isCleaning = false
    }

    func noteFileChanges(_ batch: FileChangeBatch) {
        guard !candidates.isEmpty else { return }
        if batch.requiresFullRescan || batch.affects([FileManager.default.homeDirectoryForCurrentUser]) {
            isStale = true
        }
    }
}
