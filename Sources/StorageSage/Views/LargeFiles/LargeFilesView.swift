//
//  LargeFilesView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import SwiftUI

struct LargeFilesView: View {
    @EnvironmentObject private var viewModel: LargeFilesViewModel
    @EnvironmentObject private var fileChanges: FSEventsMonitor

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.isScanning {
                ProgressView("Scanning personal folders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.files.isEmpty {
                EmptyStateView(
                    title: viewModel.scannedAt == nil ? "Find large files" : "No large files found",
                    message: "StorageSage analyzes your personal folders without changing any files.",
                    icon: SidebarPage.largeFiles.icon
                )
            } else {
                List(viewModel.sortedFiles) { file in
                    LargeFileRow(file: file) { viewModel.reveal(file) }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Large Files")
        .onChange(of: fileChanges.revision) {
            viewModel.noteFileChanges(fileChanges.latestBatch)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Large & Old Files").font(.largeTitle.bold())
                Text("Review large files in Desktop, Documents, Downloads, Movies, Music, and Pictures.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isStale {
                Label("Files changed", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.orange)
            }
            Picker("Minimum Size", selection: $viewModel.minimumSize) {
                Text("100 MB+").tag(Int64(100_000_000))
                Text("500 MB+").tag(Int64(500_000_000))
                Text("1 GB+").tag(Int64(1_000_000_000))
            }
            .frame(width: 130)
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(LargeFilesViewModel.SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 150)
            Button("Analyze Files") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning)
        }
        .padding(24)
    }
}

private struct LargeFileRow: View {
    let file: LargeFileRecord
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.headline).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(file.size.fileSize).font(.headline.monospacedDigit())
                Text(file.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Date unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Show in Finder", action: reveal)
        }
        .padding(.vertical, 5)
    }
}
