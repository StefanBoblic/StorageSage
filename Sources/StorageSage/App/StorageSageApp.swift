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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(largeFilesViewModel)
                .environmentObject(appLeftoversViewModel)
                .environmentObject(duplicatesViewModel)
                .frame(minWidth: 980, minHeight: 660)
                .task { await viewModel.scanIfNeeded() }
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
                .frame(width: 560, height: 540)
        }
    }
}
