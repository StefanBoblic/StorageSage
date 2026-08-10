//
//  APFSSnapshotsView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import SwiftUI

struct APFSSnapshotsView: View {
    @EnvironmentObject private var viewModel: APFSSnapshotsViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.isScanning {
                ProgressView("Reading APFS metadata…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.snapshots.isEmpty {
                EmptyStateView(
                    title: viewModel.hasScanned ? "No snapshots reported" : "Inspect APFS snapshots",
                    message: "StorageSage reads snapshot metadata but never deletes snapshots.",
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
            } else {
                List(viewModel.snapshots) { snapshot in
                    HStack(spacing: 12) {
                        Image(systemName: snapshot.kind == "Time Machine" ? "externaldrive.badge.timemachine" : "internaldrive.fill")
                            .font(.title2).foregroundStyle(.indigo).frame(width: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.kind).font(.headline)
                            Text(snapshot.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(snapshot.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "System managed")
                            Text(snapshot.isPurgeable ? "Purgeable" : "Protected")
                                .foregroundStyle(snapshot.isPurgeable ? .green : .secondary)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("APFS Snapshots")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("APFS Snapshot Inspector").font(.largeTitle.bold())
                Text("Snapshots can retain deleted blocks. Per-snapshot reclaimable size is not reliably exposed by macOS.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("Analysis Only", systemImage: "eye.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Button("Inspect") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning)
        }
        .padding(24)
    }
}
