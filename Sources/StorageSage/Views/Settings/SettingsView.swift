//
//  SettingsView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(StoragePreferenceKeys.dryRun) private var dryRun = false
    @AppStorage(StoragePreferenceKeys.maximumConcurrentScans)
    private var maximumConcurrentScans = UserDefaultsScanConfiguration.recommendedConcurrency
    @State private var whitelistPaths: [String] = []

    private let whitelistStore = UserDefaultsWhitelistStore()

    var body: some View {
        Form {
            Section("Safety") {
                Toggle("Dry Run", isOn: $dryRun)
                Text("Preview cleanup results without moving or deleting anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Protected Locations")
                        Spacer()
                        Button("Add Folder…", action: chooseWhitelistFolder)
                    }
                    if whitelistPaths.isEmpty {
                        Text("No custom locations are protected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(whitelistPaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                Text(abbreviated(path))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    whitelistStore.remove(path: path)
                                    reloadWhitelist()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .help("Remove from Whitelist")
                            }
                        }
                    }
                }
            }

            Section("Performance") {
                Stepper(value: $maximumConcurrentScans, in: 1...8) {
                    LabeledContent("Parallel Scan Tasks", value: "\(maximumConcurrentScans)")
                }
                Text("More tasks can speed up SSD scans, but values above 6 may increase disk contention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                LabeledContent {
                    Button("Open Full Disk Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Protected Folders")
                        Text("Optional access for Mail, Messages, and Trash analysis.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                LabeledContent("StorageSage", value: "1.0")
                Text("A private, on-device storage analyzer for macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: reloadWhitelist)
    }

    private func chooseWhitelistFolder() {
        let panel = NSOpenPanel()
        panel.title = "Protect a Folder"
        panel.prompt = "Protect"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            whitelistStore.add(url)
            reloadWhitelist()
        }
    }

    private func reloadWhitelist() {
        whitelistPaths = whitelistStore.whitelistedURLs().map(\.path).sorted()
    }

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}
