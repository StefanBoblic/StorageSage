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
        Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) { store.load() }.value
            self?.records = loaded
        }
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
        let store = store
        Task { [weak self] in
            await Task.detached(priority: .utility) { store.append(entry) }.value
            let loaded = await Task.detached(priority: .utility) { store.load() }.value
            self?.records = loaded
        }
    }

    func clear() {
        records = []
        let store = store
        Task.detached(priority: .utility) { store.clear() }
    }
}
