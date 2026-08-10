//
//  DuplicatesViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import AppKit
import Foundation

@MainActor
final class DuplicatesViewModel: ObservableObject {
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var preparedCandidates: [CleanupCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isVerifying = false
    @Published private(set) var isCleaning = false
    @Published private(set) var lastReport: CleanupReport?
    @Published var minimumSize: Int64 = 1_000_000

    private let analyzer: any DuplicateFileAnalyzing
    private let cleaner: any StorageCleaning

    init(
        analyzer: any DuplicateFileAnalyzing = DuplicateFileAnalyzer(),
        cleaner: any StorageCleaning = StorageCleaner()
    ) {
        self.analyzer = analyzer
        self.cleaner = cleaner
    }

    var selectedSize: Int64 {
        groups.flatMap(\.files).filter { selectedPaths.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var preparedSize: Int64 { preparedCandidates.reduce(0) { $0 + $1.size } }
    var potentialSavings: Int64 { groups.reduce(0) { $0 + $1.reclaimableSize } }
    var canModifySelection: Bool { !isScanning && !isVerifying && !isCleaning }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        selectedPaths.removeAll()
        preparedCandidates.removeAll()
        let analyzer = analyzer
        let threshold = minimumSize
        groups = await analyzer.analyze(minimumSize: threshold)
        isScanning = false
    }

    func toggle(_ file: DuplicateFileRecord, in group: DuplicateGroup) {
        guard canModifySelection else { return }
        preparedCandidates.removeAll()
        lastReport = nil
        if selectedPaths.contains(file.id) {
            selectedPaths.remove(file.id)
            return
        }
        let selectedInGroup = group.files.filter { selectedPaths.contains($0.id) }.count
        guard selectedInGroup < group.files.count - 1 else { return }
        selectedPaths.insert(file.id)
    }

    @discardableResult
    func verifySelection() async -> Bool {
        guard !selectedPaths.isEmpty, canModifySelection else { return false }
        isVerifying = true
        let analyzer = analyzer
        let paths = selectedPaths
        let currentGroups = groups
        preparedCandidates = await analyzer.verifiedCleanupCandidates(
            groups: currentGroups,
            selectedPaths: paths
        )
        selectedPaths = Set(preparedCandidates.map(\.id))
        isVerifying = false
        return !preparedCandidates.isEmpty
    }

    func cleanSelected() async {
        guard !preparedCandidates.isEmpty, canModifySelection else { return }
        isCleaning = true
        let analyzer = analyzer
        let paths = selectedPaths
        let currentGroups = groups
        let reverifiedCandidates = await analyzer.verifiedCleanupCandidates(
            groups: currentGroups,
            selectedPaths: paths
        )
        guard !reverifiedCandidates.isEmpty else {
            preparedCandidates.removeAll()
            selectedPaths.removeAll()
            isCleaning = false
            return
        }
        let cleaner = cleaner
        lastReport = await Task.detached(priority: .userInitiated) {
            cleaner.clean(reverifiedCandidates) { _ in }
        }.value
        selectedPaths.removeAll()
        preparedCandidates.removeAll()
        if lastReport?.removedCount ?? 0 > 0 { await scan() }
        isCleaning = false
    }

    func reveal(_ file: DuplicateFileRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
}
