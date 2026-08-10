//
//  AppLeftoversView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import SwiftUI

struct AppLeftoversView: View {
    @EnvironmentObject private var viewModel: AppLeftoversViewModel
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
        .navigationTitle("App Leftovers")
        .confirmationDialog("Review app leftovers?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(dryRun ? "Preview Only" : "Move to Trash", role: dryRun ? nil : .destructive) {
                Task {
                    await viewModel.cleanSelected()
                    showingReport = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(dryRun
                 ? "StorageSage will validate \(viewModel.selectedSize.fileSize). No files will be changed."
                 : "Move \(viewModel.selectedSize.fileSize) of possible leftovers to Trash? Review the bundle identifiers carefully before continuing.")
        }
        .alert("Leftover Cleanup Finished", isPresented: $showingReport) {
            Button("Done") { }
        } message: {
            if let report = viewModel.lastReport {
                Text(report.isDryRun
                     ? "Validated \(report.previewedCount) items totaling \(report.estimatedReclaimable.fileSize)."
                     : "Moved \(report.movedToTrashCount) items totaling \(report.movedToTrashBytes.fileSize) to Trash.")
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
                    .disabled(!viewModel.canModifySelection)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.bundleIdentifier).font(.headline)
                        Text("\(record.locationName) · \(record.url.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                    if await viewModel.prepareSelection() { showingConfirmation = true }
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
}
