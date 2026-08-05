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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
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
                .frame(width: 520, height: 300)
        }
    }
}
