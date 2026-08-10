//
//  CleanupHistoryViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

@MainActor
final class CleanupHistoryViewModel: ObservableObject {
    @Published private(set) var records: [CleanupHistoryRecord] = []
    private let store: any CleanupHistoryStoring

    init(store: any CleanupHistoryStoring = DiskCleanupHistoryStore()) {
        self.store = store
        records = store.load()
    }

    func record(source: String, candidates: [CleanupCandidate], report: CleanupReport) {
        let entry = CleanupHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            source: source,
            items: candidates.map {
                CleanupHistoryItem(path: $0.path, name: $0.name, estimatedBytes: $0.size)
            },
            movedToTrashBytes: report.movedToTrashBytes,
            deletedImmediatelyBytes: report.deletedImmediatelyBytes,
            actualFreedBytes: report.actualFreedBytes,
            isDryRun: report.isDryRun,
            errorCount: report.errors.count,
            skippedCount: report.skipped.count
        )
        store.append(entry)
        records = store.load()
    }

    func clear() {
        store.clear()
        records = []
    }
}
