//
//  ApplicationsView.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @State private var searchText = ""

    private var applications: [CleanupCandidate] {
        viewModel.candidates.filter {
            $0.category == .applications &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var appData: [CleanupCandidate] {
        viewModel.candidates.filter {
            $0.category == .appData &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Applications & Data").font(.largeTitle.bold())
                    Text("Large apps and persistent data are shown for analysis. StorageSage does not uninstall them automatically.")
                        .foregroundStyle(.secondary)
                }
                section("Installed Applications", items: applications)
                section("Persistent Application Data", items: appData)
            }
            .padding(28)
        }
        .navigationTitle("Applications")
        .searchable(text: $searchText, prompt: "Search apps and data")
    }

    private func section(_ title: String, items: [CleanupCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.bold())
                Text("\(items.count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule())
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    CandidateRow(candidate: item, showsSelection: false)
                    if index < items.count - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45)) }
        }
    }
}
