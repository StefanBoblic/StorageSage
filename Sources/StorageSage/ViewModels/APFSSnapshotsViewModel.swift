//
//  APFSSnapshotsViewModel.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

@MainActor
final class APFSSnapshotsViewModel: ObservableObject {
    @Published private(set) var snapshots: [APFSSnapshotRecord] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false

    private let analyzer: any APFSSnapshotAnalyzing

    init(analyzer: any APFSSnapshotAnalyzing = APFSSnapshotAnalyzer()) {
        self.analyzer = analyzer
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let analyzer = analyzer
        snapshots = await Task.detached(priority: .utility) { analyzer.analyze() }.value
        hasScanned = true
        isScanning = false
    }
}
