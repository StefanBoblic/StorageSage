//
//  StorageSageApp.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

@main
struct StorageSageApp: App {
    @StateObject private var viewModel = StorageViewModel()
    @StateObject private var largeFilesViewModel = LargeFilesViewModel()
    @StateObject private var appLeftoversViewModel = AppLeftoversViewModel()
    @StateObject private var duplicatesViewModel = DuplicatesViewModel()
    @StateObject private var fileChanges = FSEventsMonitor()
    @StateObject private var recommendationsViewModel = RecommendationsViewModel()
    @StateObject private var snapshotsViewModel = APFSSnapshotsViewModel()
    @StateObject private var cleanupHistory = CleanupHistoryViewModel()
    @StateObject private var diskGrowth = DiskGrowthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(largeFilesViewModel)
                .environmentObject(appLeftoversViewModel)
                .environmentObject(duplicatesViewModel)
                .environmentObject(fileChanges)
                .environmentObject(recommendationsViewModel)
                .environmentObject(snapshotsViewModel)
                .environmentObject(cleanupHistory)
                .environmentObject(diskGrowth)
                .frame(minWidth: 980, minHeight: 660)
                .task { await viewModel.scanIfNeeded() }
                .task { fileChanges.start() }
                .task { await diskGrowth.load() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Storage") {
                    Task { await viewModel.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(diskGrowth)
                .frame(width: 560, height: 540)
        }
    }
}
