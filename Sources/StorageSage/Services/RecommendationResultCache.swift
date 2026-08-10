//
//  RecommendationResultCache.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import Foundation

protocol RecommendationResultCaching: Sendable {
    func load(maxAge: TimeInterval) -> [CleanupCandidate]?
    func save(_ candidates: [CleanupCandidate])
}

struct DiskRecommendationResultCache: RecommendationResultCaching {
    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load(maxAge: TimeInterval) -> [CleanupCandidate]? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(RecommendationCacheArchive.self, from: data),
              Date().timeIntervalSince(archive.createdAt) <= maxAge else { return nil }
        return archive.candidates.map(\.candidate)
    }

    func save(_ candidates: [CleanupCandidate]) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let archive = RecommendationCacheArchive(
                createdAt: Date(),
                candidates: candidates.compactMap(CachedRecommendationCandidate.init)
            )
            try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
        } catch {
            // Recommendation caching is an optional performance optimization.
        }
    }

    private static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StorageSage", isDirectory: true)
            .appendingPathComponent("recommendations.json", isDirectory: false)
    }
}

private struct RecommendationCacheArchive: Codable {
    let createdAt: Date
    let candidates: [CachedRecommendationCandidate]
}

private struct CachedRecommendationCandidate: Codable {
    enum Strategy: String, Codable { case reviewedFile, reviewedDirectory }

    let id: String
    let name: String
    let detail: String
    let path: String
    let category: StorageCategory
    let safety: SafetyLevel
    let strategy: Strategy
    let size: Int64
    let modifiedAt: Date?

    init?(_ candidate: CleanupCandidate) {
        switch candidate.strategy {
        case .trashReviewedFile: strategy = .reviewedFile
        case .trashReviewedDirectory: strategy = .reviewedDirectory
        default: return nil
        }
        id = candidate.id
        name = candidate.name
        detail = candidate.detail
        path = candidate.path
        category = candidate.category
        safety = candidate.safety
        size = candidate.size
        modifiedAt = candidate.modifiedAt
    }

    var candidate: CleanupCandidate {
        let url = URL(fileURLWithPath: path)
        return CleanupCandidate(
            id: id,
            name: name,
            detail: detail,
            path: path,
            category: category,
            safety: safety,
            strategy: strategy == .reviewedFile ? .trashReviewedFile(url) : .trashReviewedDirectory(url),
            size: size,
            modifiedAt: modifiedAt
        )
    }
}
