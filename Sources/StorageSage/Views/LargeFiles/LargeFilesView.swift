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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Large & Old Files")
                    .font(.largeTitle.bold())
                Spacer()
                if viewModel.isStale {
                    Label("Files changed", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Analyze Files") { Task { await viewModel.scan() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isScanning)
            }

            HStack(spacing: 16) {
                Text("Review large files in Desktop, Documents, Downloads, Movies, Music, and Pictures.")
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                Spacer(minLength: 16)
                pickerField(title: "Minimum Size", width: 130) {
                    minimumSizeMenu
                }
                pickerField(title: "Sort", width: 150) {
                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(LargeFilesViewModel.SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                }
            }
        }
        .padding(24)
    }

    private var minimumSizeMenu: some View {
        Menu {
            minimumSizeButton("100 MB+", value: 100_000_000)
            minimumSizeButton("500 MB+", value: 500_000_000)
            minimumSizeButton("1 GB+", value: 1_000_000_000)
        } label: {
            HStack(spacing: 8) {
                Text(minimumSizeTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: 130, height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Minimum Size")
        .accessibilityValue(minimumSizeTitle)
    }

    private var minimumSizeTitle: String {
        switch viewModel.minimumSize {
        case 100_000_000: "100 MB+"
        case 500_000_000: "500 MB+"
        case 1_000_000_000: "1 GB+"
        default: viewModel.minimumSize.fileSize
        }
    }

    @ViewBuilder
    private func minimumSizeButton(_ title: String, value: Int64) -> some View {
        Button {
            viewModel.minimumSize = value
        } label: {
            if viewModel.minimumSize == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func pickerField<Content: View>(
        title: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fixedSize()
            content()
                .labelsHidden()
                .frame(width: width)
        }
        .fixedSize(horizontal: true, vertical: false)
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
