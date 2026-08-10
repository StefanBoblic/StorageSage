//
//  AppLeftoversView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import AppKit
import SwiftUI

struct AppLeftoversView: View {
    @EnvironmentObject private var viewModel: AppLeftoversViewModel
    @EnvironmentObject private var history: CleanupHistoryViewModel
    @EnvironmentObject private var fileChanges: FSEventsMonitor
    @AppStorage(StoragePreferenceKeys.dryRun) private var dryRun = false
    @State private var showingConfirmation = false
    @State private var showingReport = false
    @State private var showingUnavailableItems = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if !viewModel.selectedIDs.isEmpty { selectionBar }
        }
        .navigationTitle("App Leftovers")
        .onChange(of: fileChanges.revision) {
            viewModel.noteFileChanges(fileChanges.latestBatch)
        }
        .confirmationDialog("Review app leftovers?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(dryRun ? "Preview Only" : "Move to Trash", role: dryRun ? nil : .destructive) {
                Task {
                    let selectedCandidates = viewModel.selectedRecords.map(\.cleanupCandidate)
                    await viewModel.cleanSelected()
                    if let report = viewModel.lastReport {
                        history.record(source: "App Leftovers", candidates: selectedCandidates, report: report)
                    }
                    showingReport = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(dryRun
                 ? "StorageSage will validate \(viewModel.selectedSize.fileSize). No files will be changed."
                 : "Move \(viewModel.selectedSize.fileSize) of possible leftovers to Trash? Review the bundle identifiers carefully before continuing.")
        }
        .alert("Some Leftovers Are Unavailable", isPresented: $showingUnavailableItems) {
            if !viewModel.selectedIDs.isEmpty {
                Button("Continue with Available Items") { showingConfirmation = true }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(unavailableItemsMessage)
        }
        .alert("Leftover Cleanup Finished", isPresented: $showingReport) {
            if let report = viewModel.lastReport, !report.skipped.isEmpty || !report.errors.isEmpty {
                Button("Copy Details") { copyReportDetails(report) }
            }
            Button("Done") { }
        } message: {
            if let report = viewModel.lastReport {
                Text(reportMessage(report))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Removed App Leftovers").font(.largeTitle.bold())
                Text("High-confidence bundle-ID files with no matching installed application. Always review before removal.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !viewModel.records.isEmpty {
                Button(selectAllTitle) {
                    viewModel.toggleAll()
                }
                .disabled(!viewModel.canModifySelection || viewModel.selectableRecords.isEmpty)
            }
            Button("Analyze Leftovers") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning || viewModel.isCleaning)
        }
        .padding(24)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isScanning {
            ProgressView("Comparing app identifiers…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.records.isEmpty {
            EmptyStateView(title: "No leftovers to review", message: "Run the analyzer to compare application bundle identifiers.", icon: "shippingbox.and.arrow.backward")
        } else {
            List(viewModel.records) { record in
                HStack(spacing: 12) {
                    Button { viewModel.toggle(record) } label: {
                        Image(systemName: viewModel.selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canModifySelection || !record.canMoveToTrash)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.bundleIdentifier).font(.headline)
                        Text("\(record.locationName) · \(record.url.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !record.canMoveToTrash {
                            Label("Full Disk Access required", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Text(record.size.fileSize).font(.headline.monospacedDigit())
                    Button("Show in Finder") { viewModel.reveal(record) }
                }
                .padding(.vertical, 5)
            }
            .listStyle(.inset)
        }
    }

    private var selectionBar: some View {
        HStack {
            Text("\(viewModel.selectedIDs.count) selected · \(viewModel.selectedSize.fileSize)")
                .font(.headline)
            Spacer()
            Button {
                Task {
                    let canContinue = await viewModel.prepareSelection()
                    if !viewModel.unavailableSelectionNames.isEmpty {
                        showingUnavailableItems = true
                    } else if canContinue {
                        showingConfirmation = true
                    }
                }
            } label: {
                if viewModel.isPreparing { ProgressView().controlSize(.small) }
                else { Text(dryRun ? "Measure & Preview" : "Measure & Review") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canModifySelection)
        }
        .padding(14)
        .background(.bar)
    }

    private var selectAllTitle: String {
        if viewModel.areAllRecordsSelected { return "Deselect All" }
        return viewModel.unavailableRecords.isEmpty ? "Select All" : "Select Available"
    }

    private var unavailableItemsMessage: String {
        let names = viewModel.unavailableSelectionNames.prefix(5).joined(separator: ", ")
        let remaining = viewModel.unavailableSelectionNames.count - min(viewModel.unavailableSelectionNames.count, 5)
        let suffix = remaining > 0 ? " and \(remaining) more" : ""
        return "StorageSage cannot move \(names)\(suffix) to Trash. Grant Full Disk Access, then analyze leftovers again."
    }

    private func reportMessage(_ report: CleanupReport) -> String {
        if report.isDryRun {
            var lines = ["Validated \(report.previewedCount) items totaling \(report.estimatedReclaimable.fileSize)."]
            if !report.skipped.isEmpty { lines.append(issueSummary(title: "Skipped", values: report.skipped)) }
            if !report.errors.isEmpty { lines.append(issueSummary(title: "Failed", values: report.errors)) }
            return lines.joined(separator: "\n\n")
        }

        var lines = ["Moved \(report.movedToTrashCount) items totaling \(report.movedToTrashBytes.fileSize) to Trash."]
        if !report.skipped.isEmpty { lines.append(issueSummary(title: "Skipped", values: report.skipped)) }
        if !report.errors.isEmpty { lines.append(issueSummary(title: "Failed", values: report.errors)) }
        return lines.joined(separator: "\n\n")
    }

    private func issueSummary(title: String, values: [String]) -> String {
        let visible = values.prefix(3).joined(separator: "\n")
        let remaining = values.count - min(values.count, 3)
        let suffix = remaining > 0 ? "\n…and \(remaining) more. Use Copy Details for the full report." : ""
        return "\(title) \(values.count) items:\n\(visible)\(suffix)"
    }

    private func copyReportDetails(_ report: CleanupReport) {
        var sections: [String] = []
        if !report.skipped.isEmpty { sections.append("Skipped:\n" + report.skipped.joined(separator: "\n")) }
        if !report.errors.isEmpty { sections.append("Errors:\n" + report.errors.joined(separator: "\n")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
    }
}
