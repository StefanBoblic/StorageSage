//
//  CandidateNameProvider.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol CandidateNameProviding: Sendable {
    func displayName(for url: URL) -> String
}

struct CandidateNameProvider: CandidateNameProviding {
    func displayName(for url: URL) -> String {
        let rawName = url.deletingPathExtension().lastPathComponent
        let knownNames: [String: String] = [
            "com.spotify.client": "Spotify Cache",
            "com.openai.codex": "Codex Cache",
            "org.swift.swiftpm": "Swift Package Manager",
            "go-build": "Go Build Cache",
            "tuist-cloud": "Tuist Cloud Cache",
            "codex-runtimes": "Codex Runtimes"
        ]
        if let knownName = knownNames[rawName] { return knownName }

        return rawName
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "org.", with: "")
            .replacingOccurrences(of: ".", with: " · ")
    }
}
