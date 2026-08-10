//
//  ContentView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @State private var selection: SidebarPage? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarPage.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.icon)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    if viewModel.volume.total > 0 {
                        StorageProgressBar(fraction: viewModel.volume.usedFraction, height: 7)
                        HStack {
                            Text("\(viewModel.volume.available.fileSize) available")
                            Spacer()
                            Text("\(Int(viewModel.volume.usedFraction * 100))% used")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(selection: $selection)
                case .cleanup: CleanupView()
                case .applications: ApplicationsView()
                case .largeFiles: LargeFilesView()
                case .leftovers: AppLeftoversView()
                case .duplicates: DuplicatesView()
                case .recommendations: RecommendationsView()
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        Task { await viewModel.scan() }
                    } label: {
                        Label("Scan Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isScanning || viewModel.isCleaning)
                }
            }
        }
        .overlay {
            if viewModel.isScanning && viewModel.candidates.isEmpty {
                ScanningOverlay()
            }
        }
    }
}

private struct ScanningOverlay: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 5) {
                Text("Analyzing your Mac")
                    .font(.title3.weight(.semibold))
                Text("Scanning caches, developer tools, simulators, and application data…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 24, y: 8)
    }
}

struct StorageProgressBar: View {
    let fraction: Double
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fraction > 0.9 ? Color.red.gradient : Color.accentColor.gradient)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
    }
}
