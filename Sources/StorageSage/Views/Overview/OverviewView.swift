//
//  OverviewView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @Binding var selection: SidebarPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                storageCard
                categoryGrid
                opportunities
            if !viewModel.inaccessiblePaths.isEmpty { privacyNotice }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .navigationTitle("StorageSage")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Storage Overview")
                    .font(.largeTitle.bold())
            Text(overviewStatus)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.cleanableSize > 0 {
                Button("Review \(viewModel.cleanableSize.fileSize)") { selection = .cleanup }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var overviewStatus: String {
        if viewModel.isUsingCachedScan && viewModel.isScanning, let scannedAt = viewModel.scannedAt {
            return "Showing \(scannedAt.formatted(date: .abbreviated, time: .shortened)) analysis · Refreshing…"
        }
        return viewModel.scannedAt.map {
            "Last analyzed \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? "Preparing your first analysis…"
    }

    private var storageCard: some View {
        HStack(spacing: 26) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 15)
                Circle()
                    .trim(from: 0, to: min(viewModel.volume.usedFraction, 1))
                    .stroke(
                        viewModel.volume.usedFraction > 0.9 ? Color.red.gradient : Color.accentColor.gradient,
                        style: StrokeStyle(lineWidth: 15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(Int(viewModel.volume.usedFraction * 100))%")
                        .font(.title2.bold().monospacedDigit())
                    Text("used").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 126, height: 126)

            VStack(alignment: .leading, spacing: 13) {
                Label("Macintosh HD", systemImage: "internaldrive.fill")
                    .font(.title3.weight(.semibold))
                StorageProgressBar(fraction: viewModel.volume.usedFraction, height: 12)
                HStack(spacing: 28) {
                    Metric(label: "Used", value: viewModel.volume.used.fileSize)
                    Metric(label: "Available", value: viewModel.volume.available.fileSize)
                    Metric(label: "Capacity", value: viewModel.volume.total.fileSize)
                }
                if viewModel.volume.usedFraction > 0.9 {
                    Label("Storage is critically low. macOS and apps may run more slowly.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(24)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.separator.opacity(0.5)) }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What is taking up space").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(viewModel.categoryTotals, id: \.0) { category, total in
                    HStack(spacing: 13) {
                        Image(systemName: category.icon)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(category.color.gradient, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.rawValue).font(.headline)
                            Text(total.fileSize).font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        Spacer()
                    }
                    .padding(15)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45)) }
                }
            }
        }
    }

    private var opportunities: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Top cleanup opportunities").font(.title2.bold())
                Spacer()
                Button("View All") { selection = .cleanup }
            }
            VStack(spacing: 0) {
                ForEach(Array(viewModel.candidates.filter(\.isCleanable).prefix(5).enumerated()), id: \.element.id) { index, item in
                    CandidateRow(candidate: item, showsSelection: false)
                    if index < min(viewModel.candidates.filter(\.isCleanable).count, 5) - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45)) }
        }
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.blue).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Some protected folders were not analyzed").font(.headline)
                Text("Grant Full Disk Access in System Settings if you want StorageSage to include Mail, Messages, and Trash. The app works without it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
