//
//  RecommendationsView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject private var viewModel: RecommendationsViewModel
    @EnvironmentObject private var fileChanges: FSEventsMonitor
    @EnvironmentObject private var history: CleanupHistoryViewModel
    @AppStorage(StoragePreferenceKeys.dryRun) private var dryRun = false
    @State private var showingConfirmation = false
    @State private var showingReport = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if !viewModel.selectedIDs.isEmpty { selectionBar }
        }
        .navigationTitle("Recommendations")
        .task { await viewModel.loadCachedResults() }
        .onChange(of: fileChanges.revision) { viewModel.noteFileChanges(fileChanges.latestBatch) }
        .confirmationDialog("Review selected files?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(dryRun ? "Preview Only" : "Move to Trash", role: dryRun ? nil : .destructive) {
                Task {
                    let selectedCandidates = viewModel.selectedCandidates
                    await viewModel.cleanSelected()
                    if let report = viewModel.lastReport {
                        history.record(source: "Recommendations", candidates: selectedCandidates, report: report)
                    }
                    showingReport = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(dryRun
                 ? "Validate \(viewModel.selectedSize.fileSize) without changing files?"
                 : "Move \(viewModel.selectedSize.fileSize) to Trash? Every file was measured again.")
        }
        .alert("Recommendation Cleanup Finished", isPresented: $showingReport) {
            Button("Done") { }
        } message: {
            if let report = viewModel.lastReport {
                Text(report.isDryRun
                     ? "Validated \(report.previewedCount) files totaling \(report.estimatedReclaimable.fileSize)."
                     : "Moved \(report.movedToTrashCount) files totaling \(report.movedToTrashBytes.fileSize) to Trash.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Smart Recommendations").font(.largeTitle.bold())
                Text("Old installers, archives, and rebuildable project artifacts. Nothing is selected automatically.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isStale {
                Label("Files changed", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button("Analyze") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning || viewModel.isCleaning)
        }
        .padding(24)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isScanning && viewModel.candidates.isEmpty {
            ProgressView("Finding safe opportunities…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.candidates.isEmpty {
            EmptyStateView(title: "No recommendations yet", message: "Run the analyzer to find old installers and archives.", icon: "lightbulb")
        } else {
            List {
                if viewModel.isUsingCachedResults || viewModel.isScanning {
                    Section {
                        HStack(spacing: 10) {
                            if viewModel.isScanning { ProgressView().controlSize(.small) }
                            Image(systemName: viewModel.isUsingCachedResults ? "clock.arrow.circlepath" : "bolt.fill")
                                .foregroundStyle(.secondary)
                            Text(cacheStatus)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(viewModel.sections) { section in
                    Section {
                        if section.candidates.isEmpty && section.isScanning {
                            ProgressView("Scanning \(section.title)…").padding(.vertical, 8)
                        }
                        ForEach(section.candidates) { candidate in
                            HStack(spacing: 12) {
                                Button { viewModel.toggle(candidate) } label: {
                                    Image(systemName: viewModel.selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.name).font(.headline)
                                    Text(candidate.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(candidate.size.fileSize).font(.headline.monospacedDigit())
                            }
                            .padding(.vertical, 5)
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                            if section.isScanning { ProgressView().controlSize(.mini) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var cacheStatus: String {
        if viewModel.isUsingCachedResults && viewModel.isScanning {
            return "Showing cached results while fresh analysis runs."
        }
        if viewModel.isUsingCachedResults {
            return "Showing cached results. Run Analyze to refresh them."
        }
        return "Completed sections appear immediately while the remaining analysis continues."
    }

    private var selectionBar: some View {
        HStack {
            Text("\(viewModel.selectedIDs.count) selected · \(viewModel.selectedSize.fileSize)").font(.headline)
            Spacer()
            Button {
                Task { if await viewModel.prepareSelection() { showingConfirmation = true } }
            } label: {
                if viewModel.isPreparing { ProgressView().controlSize(.small) }
                else { Text("Measure & Review") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canModifySelection)
        }
        .padding(14)
        .background(.bar)
    }
}
