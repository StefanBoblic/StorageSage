//
//  RecommendationsViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

struct RecommendationSection: Identifiable {
    let id: String
    let title: String
    let candidates: [CleanupCandidate]
    let isScanning: Bool
}

@MainActor
final class RecommendationsViewModel: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isCleaning = false
    @Published private(set) var isStale = false
    @Published private(set) var isUsingCachedResults = false
    @Published private(set) var activeAnalyzerIDs: Set<String> = []
    @Published private(set) var lastReport: CleanupReport?

    private let analyzers: [any RecommendationAnalyzing]
    private let preflight: any CleanupPreflightMeasuring
    private let cleaner: any StorageCleaning
    private let cache: any RecommendationResultCaching
    private var resultsByAnalyzer: [String: [CleanupCandidate]] = [:]
    private var hasLoadedCache = false

    init(
        analyzers: [any RecommendationAnalyzing] = [InstallerArchiveAnalyzer(), ProjectArtifactAnalyzer()],
        preflight: any CleanupPreflightMeasuring = CleanupPreflightService(),
        cleaner: any StorageCleaning = StorageCleaner(),
        cache: any RecommendationResultCaching = DiskRecommendationResultCache()
    ) {
        self.analyzers = analyzers
        self.preflight = preflight
        self.cleaner = cleaner
        self.cache = cache
    }

    var selectedCandidates: [CleanupCandidate] { candidates.filter { selectedIDs.contains($0.id) } }
    var selectedSize: Int64 { selectedCandidates.reduce(0) { $0 + $1.size } }
    var canModifySelection: Bool { !isScanning && !isPreparing && !isCleaning }
    var sections: [RecommendationSection] {
        analyzers.map { analyzer in
            RecommendationSection(
                id: analyzer.id,
                title: analyzer.title,
                candidates: resultsByAnalyzer[analyzer.id] ?? [],
                isScanning: activeAnalyzerIDs.contains(analyzer.id)
            )
        }
    }

    func loadCachedResults() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        let cache = cache
        guard let cached = await Task.detached(priority: .utility, operation: {
            cache.load(maxAge: 7 * 24 * 60 * 60)
        }).value else { return }
        distribute(cached)
        isUsingCachedResults = true
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        selectedIDs.removeAll()
        activeAnalyzerIDs = Set(analyzers.map(\.id))
        let analyzers = analyzers

        await withTaskGroup(of: (String, [CleanupCandidate]).self) { group in
            for analyzer in analyzers {
                group.addTask { (analyzer.id, analyzer.analyze()) }
            }
            while let (id, result) = await group.next() {
                resultsByAnalyzer[id] = result.sorted { $0.size > $1.size }
                activeAnalyzerIDs.remove(id)
                rebuildCandidates()
            }
        }

        isUsingCachedResults = false
        isStale = false
        isScanning = false
        let cache = cache
        let candidates = candidates
        await Task.detached(priority: .utility) { cache.save(candidates) }.value
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
        for id in resultsByAnalyzer.keys {
            resultsByAnalyzer[id] = resultsByAnalyzer[id]?.compactMap { selectedIDs.contains($0.id) ? measured[$0.id] : $0 }
        }
        rebuildCandidates()
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
        let removedIDs = Set(selection.map(\.id))
        selectedIDs.removeAll()
        if lastReport?.removedCount ?? 0 > 0 {
            for id in resultsByAnalyzer.keys {
                resultsByAnalyzer[id]?.removeAll { removedIDs.contains($0.id) }
            }
            rebuildCandidates()
            let cache = cache
            let candidates = candidates
            Task.detached(priority: .utility) { cache.save(candidates) }
        }
        isCleaning = false
    }

    func noteFileChanges(_ batch: FileChangeBatch) {
        guard !candidates.isEmpty else { return }
        if batch.requiresFullRescan || batch.affects([FileManager.default.homeDirectoryForCurrentUser]) {
            isStale = true
        }
    }

    private func distribute(_ values: [CleanupCandidate]) {
        resultsByAnalyzer["installers"] = values.filter { $0.category == .installers }
        resultsByAnalyzer["project-artifacts"] = values.filter { $0.category == .projectArtifacts }
        rebuildCandidates()
    }

    private func rebuildCandidates() {
        candidates = resultsByAnalyzer.values.flatMap { $0 }.sorted { $0.size > $1.size }
    }
}
