//
//  CandidateRow.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import SwiftUI

struct CandidateRow: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    let candidate: CleanupCandidate
    var showsSelection = true

    var body: some View {
        HStack(spacing: 13) {
            if showsSelection && candidate.isCleanable {
                Button { viewModel.toggle(candidate) } label: {
                    Image(systemName: viewModel.selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedIDs.contains(candidate.id) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canModifySelection)
                .accessibilityLabel(viewModel.selectedIDs.contains(candidate.id) ? "Deselect" : "Select")
            }
            Image(systemName: candidate.category.icon)
                .font(.title3)
                .foregroundStyle(candidate.category.color)
                .frame(width: 36, height: 36)
                .background(candidate.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name).font(.headline).lineLimit(1)
                Text(candidate.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                Text(candidate.size.fileSize).font(.headline.monospacedDigit())
                Label(candidate.safety.rawValue, systemImage: candidate.safety.icon)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(candidate.safety.color)
            }
            Menu {
                Button("Show in Finder") { viewModel.reveal(candidate) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(candidate.path, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if showsSelection && viewModel.canModifySelection { viewModel.toggle(candidate) }
        }
    }
}
