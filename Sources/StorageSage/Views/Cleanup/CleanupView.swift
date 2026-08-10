//
//  CleanupView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @AppStorage(StoragePreferenceKeys.dryRun) private var dryRun = false
    @State private var searchText = ""
    @State private var category: StorageCategory?
    @State private var showingConfirmation = false
    @State private var showingReport = false

    private var filtered: [CleanupCandidate] {
        viewModel.candidates.filter { item in
            item.category != .applications &&
            (category == nil || item.category == category) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) || item.path.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty && !viewModel.isScanning {
                EmptyStateView(title: "Nothing to review", message: "Run a scan or change your filters.", icon: "sparkles")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { candidate in
                            CandidateRow(candidate: candidate)
                            Divider().padding(.leading, 66)
                        }
                    }
                }
            }
            selectionBar
        }
        .navigationTitle("Cleanup")
        .searchable(text: $searchText, prompt: "Search storage items")
        .confirmationDialog(
            dryRun ? "Preview selected items?" : "Remove selected items?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button(dryRun ? "Validate Selection" : "Continue", role: dryRun ? nil : .destructive) {
                Task {
                    await viewModel.cleanSelected()
                    showingReport = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(confirmationMessage)
        }
        .alert(viewModel.lastReport?.isDryRun == true ? "Dry Run Finished" : "Cleanup Finished", isPresented: $showingReport) {
            Button("Done") { }
        } message: {
            if let report = viewModel.lastReport {
                Text(reportMessage(report))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Cleanup Items").font(.largeTitle.bold())
                    Text("Nothing is removed until you select it and confirm.").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("All Categories") { category = nil }
                    Divider()
                    ForEach(StorageCategory.allCases.filter { $0 != .applications }) { item in
                        Button(item.rawValue) { category = item }
                    }
                } label: {
                    Label(category?.rawValue ?? "All Categories", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            HStack(spacing: 10) {
                Button("Select Safe Items") { viewModel.selectSafeItems() }
                Button("Clear Selection") { viewModel.clearSelection() }.disabled(viewModel.selectedIDs.isEmpty)
                Spacer()
                Label("Analysis Only items cannot be selected", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var selectionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selectedCandidates.count) selected").font(.headline)
                Text("Estimated total: \(viewModel.selectedSize.fileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.selectedTrashSize > 0 || viewModel.selectedImmediateDeletionSize > 0 {
                    Text(selectionBreakdown)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if viewModel.isScanning || viewModel.isUsingCachedScan {
                Label("Refreshing size estimates…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let progress = viewModel.cleanupProgress {
                CleanupProgressSummary(progress: progress)
            }
            Button(dryRun ? "Preview Selected" : "Remove Selected") { showingConfirmation = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canCleanSelection)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var confirmationMessage: String {
        if dryRun {
            return "StorageSage will validate the current \(viewModel.selectedSize.fileSize) estimate. No files will be changed."
        }
        var lines: [String] = []
        if viewModel.selectedTrashSize > 0 {
            lines.append("Move approximately \(viewModel.selectedTrashSize.fileSize) to Trash. This does not free disk space until Trash is emptied.")
        }
        if viewModel.selectedImmediateDeletionSize > 0 {
            lines.append("Delete approximately \(viewModel.selectedImmediateDeletionSize.fileSize) of unavailable Simulator data immediately. This cannot be undone.")
        }
        lines.append("Close affected apps before continuing.")
        return lines.joined(separator: "\n\n")
    }

    private var selectionBreakdown: String {
        var parts: [String] = []
        if viewModel.selectedTrashSize > 0 {
            parts.append("Trash \(viewModel.selectedTrashSize.fileSize)")
        }
        if viewModel.selectedImmediateDeletionSize > 0 {
            parts.append("Immediate \(viewModel.selectedImmediateDeletionSize.fileSize)")
        }
        return parts.joined(separator: " · ")
    }

    private func reportMessage(_ report: CleanupReport) -> String {
        var lines: [String] = []
        if report.isDryRun {
            lines.append("Validated \(report.previewedCount) items totaling approximately \(report.estimatedReclaimable.fileSize). No files were changed.")
            if report.estimatedTrashBytes > 0 {
                lines.append("Would move \(report.estimatedTrashBytes.fileSize) to Trash.")
            }
            if report.estimatedImmediateDeletionBytes > 0 {
                lines.append("Would delete \(report.estimatedImmediateDeletionBytes.fileSize) immediately.")
            }
        } else {
            if report.movedToTrashCount > 0 {
                lines.append("Moved \(report.movedToTrashCount) items totaling approximately \(report.movedToTrashBytes.fileSize) to Trash. Empty Trash to free this space.")
            }
            if report.deletedImmediatelyCount > 0 {
                lines.append("Deleted \(report.deletedImmediatelyCount) Simulator items totaling approximately \(report.deletedImmediatelyBytes.fileSize) immediately.")
            }
        }
        if !report.skipped.isEmpty {
            lines.append("Skipped:\n" + report.skipped.joined(separator: "\n"))
        }
        if !report.errors.isEmpty {
            lines.append("Errors:\n" + report.errors.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }
}

private struct CleanupProgressSummary: View {
    let progress: CleanupProgress

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 5) {
                Text(progress.isDryRun ? "Eligible" : "Handled")
                    .foregroundStyle(.secondary)
                Text("\(progress.displayedBytes.fileSize) / \(progress.totalBytes.fileSize)")
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .font(.caption)

            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
                .frame(width: 180)
            if !progress.isDryRun {
                Text("Trash \(progress.movedToTrashBytes.fileSize) · Deleted \(progress.deletedImmediatelyBytes.fileSize)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.isDryRun ? "Cleanup validation progress" : "Cleanup processing progress")
        .accessibilityValue("\(Int(progress.fractionCompleted * 100)) percent")
    }
}
