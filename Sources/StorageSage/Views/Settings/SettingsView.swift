//
//  SettingsView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
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
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Safety") {
                Label("Rebuildable files are moved to Trash whenever possible.", systemImage: "checkmark.shield.fill")
                Label("Persistent app data is analysis-only.", systemImage: "eye.fill")
                Label("Unavailable simulators require explicit confirmation.", systemImage: "exclamationmark.triangle.fill")
            }
            Section("About") {
                LabeledContent("StorageSage", value: "1.0")
                Text("A private, on-device storage analyzer for macOS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
