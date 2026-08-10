//
//  DuplicatesView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var viewModel: DuplicatesViewModel
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
            if !viewModel.selectedPaths.isEmpty { selectionBar }
        }
        .navigationTitle("Duplicates")
        .onChange(of: fileChanges.revision) {
            viewModel.noteFileChanges(fileChanges.latestBatch)
        }
        .confirmationDialog("Remove verified duplicates?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(dryRun ? "Preview Only" : "Move to Trash", role: dryRun ? nil : .destructive) {
                Task {
                    let selectedCandidates = viewModel.preparedCandidates
                    await viewModel.cleanSelected()
                    if let report = viewModel.lastReport {
                        history.record(source: "Duplicates", candidates: selectedCandidates, report: report)
                    }
                    showingReport = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("StorageSage fully rehashed every selected file and confirmed an unselected identical copy remains. \(dryRun ? "No files will be changed." : "Move \(viewModel.preparedSize.fileSize) to Trash?")")
        }
        .alert("Duplicate Cleanup Finished", isPresented: $showingReport) {
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
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Duplicate Files").font(.largeTitle.bold())
                Text("Size, partial hash, and full SHA-256 verification. At least one identical copy is always kept.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Minimum Size", selection: $viewModel.minimumSize) {
                Text("1 MB+").tag(Int64(1_000_000))
                Text("10 MB+").tag(Int64(10_000_000))
                Text("100 MB+").tag(Int64(100_000_000))
            }
            .frame(width: 125)
            Button("Find Duplicates") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning || viewModel.isCleaning)
        }
        .padding(24)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isScanning {
            ProgressView("Comparing file contents…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.groups.isEmpty {
            EmptyStateView(title: "No duplicates found", message: "Run the finder to compare files in your personal folders.", icon: "doc.on.doc")
        } else {
            List {
                ForEach(viewModel.groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            HStack(spacing: 12) {
                                Button { viewModel.toggle(file, in: group) } label: {
                                    Image(systemName: viewModel.selectedPaths.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canModifySelection)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).font(.headline)
                                    Text(file.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Show in Finder") { viewModel.reveal(file) }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("\(group.files.count) identical files · \(group.fileSize.fileSize) each · \(group.reclaimableSize.fileSize) potential savings")
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var selectionBar: some View {
        HStack {
            Text("\(viewModel.selectedPaths.count) selected · \(viewModel.selectedSize.fileSize)").font(.headline)
            Spacer()
            Button {
                Task {
                    if await viewModel.verifySelection() { showingConfirmation = true }
                }
            } label: {
                if viewModel.isVerifying { ProgressView().controlSize(.small) }
                else { Text("Verify & Review") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canModifySelection)
        }
        .padding(14)
        .background(.bar)
    }
}
