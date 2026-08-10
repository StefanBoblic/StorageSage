//
//  DiskGrowthView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Charts
import SwiftUI

struct DiskGrowthView: View {
    @EnvironmentObject private var viewModel: DiskGrowthViewModel
    @State private var showingClearConfirmation = false
    @State private var showingBaselineConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Growth Monitor")
        .confirmationDialog("Establish a new baseline?", isPresented: $showingBaselineConfirmation) {
            Button("Create Baseline") { Task { await viewModel.establishBaseline() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A new full snapshot will become the reference point. Existing history will be preserved.")
        }
        .confirmationDialog("Clear growth history?", isPresented: $showingClearConfirmation) {
            Button("Clear History", role: .destructive) { Task { await viewModel.clearHistory() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes local size snapshots only. No user files will be changed.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Disk Growth Monitor").font(.largeTitle.bold())
                Text("See which areas are growing without continuously rescanning your Mac.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.hasBaseline {
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(GrowthHistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .frame(width: 175)
                Menu {
                    Button("Establish New Baseline") { showingBaselineConfirmation = true }
                    Button("Clear Growth History", role: .destructive) { showingClearConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isMeasuring { ProgressView().controlSize(.small) }
                    else { Label("Refresh Now", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isMeasuring)
            }
        }
        .padding(24)
    }

    @ViewBuilder private var content: some View {
        if !viewModel.hasBaseline {
            ContentUnavailableView {
                Label("Start Tracking Disk Growth", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("StorageSage saves local, aggregated size snapshots. File contents are never stored or uploaded.")
            } actions: {
                Button("Create Baseline") { Task { await viewModel.establishBaseline() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMeasuring)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusBanner
                    if let comparison = viewModel.comparison {
                        summary(comparison)
                        growthChart
                        changes(comparison)
                    } else {
                        baselineReady
                    }
                }
                .padding(24)
                .frame(maxWidth: 1180, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if viewModel.isStale {
            Label("Tracked folders changed. Refresh to record the latest sizes.", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func summary(_ comparison: DiskGrowthComparison) -> some View {
        HStack(spacing: 28) {
            Image(systemName: comparison.diskDeltaBytes > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(comparison.diskDeltaBytes > 0 ? .orange : .green)
                .frame(width: 64, height: 64)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(comparison.diskDeltaBytes > 0 ? "Disk usage increased" : "Disk usage decreased")
                    .font(.headline)
                Text(signed(comparison.diskDeltaBytes))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(comparison.baseline.createdAt.formatted(date: .abbreviated, time: .shortened)) – \(comparison.current.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(comparison.current.availableBytes.fileSize).font(.title2.bold().monospacedDigit())
                Text("available now").foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.separator.opacity(0.45)) }
    }

    private var growthChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Used Space History").font(.title2.bold())
            Chart(viewModel.visibleHistory) { snapshot in
                AreaMark(
                    x: .value("Date", snapshot.createdAt),
                    y: .value("Used", snapshot.usedBytes)
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))
                LineMark(
                    x: .value("Date", snapshot.createdAt),
                    y: .value("Used", snapshot.usedBytes)
                )
                .lineStyle(.init(lineWidth: 2.5))
                PointMark(
                    x: .value("Date", snapshot.createdAt),
                    y: .value("Used", snapshot.usedBytes)
                )
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bytes = value.as(Int64.self) { Text(bytes.fileSize) }
                    }
                }
            }
            .frame(height: 230)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func changes(_ comparison: DiskGrowthComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Changes").font(.title2.bold())
            VStack(spacing: 0) {
                ForEach(Array(comparison.changes.enumerated()), id: \.element.id) { index, change in
                    GrowthChangeRow(change: change) { viewModel.reveal(change) }
                    if index < comparison.changes.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            Text("Unattributed changes may include macOS data, APFS snapshots, purgeable space, and locations StorageSage cannot access.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var baselineReady: some View {
        ContentUnavailableView(
            "Baseline Created",
            systemImage: "checkmark.circle.fill",
            description: Text("Refresh after your disk changes to see what grew or shrank.")
        )
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func signed(_ bytes: Int64) -> String {
        bytes == 0 ? "No change" : "\(bytes > 0 ? "+" : "−")\(abs(bytes).fileSize)"
    }
}

private struct GrowthChangeRow: View {
    let change: GrowthBucketChange
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(change.deltaBytes > 0 ? .orange : .green)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(change.name).font(.headline)
                if change.isUnattributed {
                    Text("Outside monitored folders").font(.caption).foregroundStyle(.secondary)
                } else if change.state == .unavailable {
                    Text("Access unavailable").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(change.previousBytes.fileSize) → \(change.currentBytes.fileSize)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(signed(change.deltaBytes)).font(.headline.monospacedDigit())
            if change.path != nil {
                Button("Show in Finder", action: reveal)
            }
        }
        .padding(13)
    }

    private var icon: String {
        if change.isUnattributed { return "internaldrive.fill" }
        return change.deltaBytes > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private func signed(_ bytes: Int64) -> String {
        bytes == 0 ? "—" : "\(bytes > 0 ? "+" : "−")\(abs(bytes).fileSize)"
    }
}
