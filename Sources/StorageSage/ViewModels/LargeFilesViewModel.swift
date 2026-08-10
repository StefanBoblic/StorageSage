//
//  LargeFilesViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import AppKit
import Foundation

@MainActor
final class LargeFilesViewModel: ObservableObject {
    enum SortOrder: String, CaseIterable, Identifiable {
        case largest = "Largest First"
        case oldest = "Oldest First"
        var id: String { rawValue }
    }

    @Published private(set) var files: [LargeFileRecord] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?
    @Published private(set) var isStale = false
    @Published var minimumSize: Int64 = 500_000_000
    @Published var sortOrder: SortOrder = .largest

    private let analyzer: any LargeFileAnalyzing

    init(analyzer: any LargeFileAnalyzing = LargeFileAnalyzer()) {
        self.analyzer = analyzer
    }

    var sortedFiles: [LargeFileRecord] {
        switch sortOrder {
        case .largest:
            return files.sorted { $0.size > $1.size }
        case .oldest:
            return files.sorted { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let analyzer = analyzer
        let threshold = minimumSize
        files = await analyzer.analyze(minimumSize: threshold)
        scannedAt = Date()
        isStale = false
        isScanning = false
    }

    func noteFileChanges(_ batch: FileChangeBatch) {
        guard scannedAt != nil else { return }
        if batch.requiresFullRescan || batch.affects(LargeFileAnalyzer.defaultRoots()) {
            isStale = true
            let analyzer = analyzer
            Task { await analyzer.invalidate(batch) }
        }
    }

    func reveal(_ file: LargeFileRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
}
