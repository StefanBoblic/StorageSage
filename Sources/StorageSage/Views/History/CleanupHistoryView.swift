//
//  CleanupHistoryView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import SwiftUI

struct CleanupHistoryView: View {
    @EnvironmentObject private var viewModel: CleanupHistoryViewModel
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.records.isEmpty {
                EmptyStateView(title: "No cleanup history", message: "Completed previews and cleanup operations will appear here.", icon: "clock")
            } else {
                List(viewModel.records) { record in
                    DisclosureGroup {
                        ForEach(record.items) { item in
                            LabeledContent(item.name, value: item.estimatedBytes.fileSize)
                            Text(item.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: record.isDryRun ? "eye.fill" : "checkmark.circle.fill")
                                .foregroundStyle(record.isDryRun ? Color.secondary : Color.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.source).font(.headline)
                                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(record.isDryRun ? "Preview" : handledBytes(record).fileSize).font(.headline.monospacedDigit())
                                if let actual = record.actualFreedBytes, !record.isDryRun {
                                    Text("Actual +\(actual.fileSize)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Cleanup History")
        .confirmationDialog("Clear cleanup history?", isPresented: $showingClearConfirmation) {
            Button("Clear History", role: .destructive) { viewModel.clear() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes only StorageSage's local history. It does not change any files or Trash contents.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Cleanup History").font(.largeTitle.bold())
                Text("A local audit of previews, cleanup actions, paths, and measured results.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear History", role: .destructive) { showingClearConfirmation = true }
                .disabled(viewModel.records.isEmpty)
        }
        .padding(24)
    }

    private func handledBytes(_ record: CleanupHistoryRecord) -> Int64 {
        record.movedToTrashBytes + record.deletedImmediatelyBytes
    }
}
