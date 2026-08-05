//
//  ScanTargetProvider.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

enum ScanMode: Sendable {
    case item
    case children(minimumSize: Int64)
}

struct ScanTarget: Sendable {
    let url: URL
    let name: String?
    let detail: String
    let category: StorageCategory
    let safety: SafetyLevel
    let mode: ScanMode
}

protocol ScanTargetProviding: Sendable {
    func targets() -> [ScanTarget]
    func protectedURLs() -> [URL]
}

struct DefaultScanTargetProvider: ScanTargetProviding {
    private let dynamicResolvers: [any DynamicScanTargetResolving]

    init(dynamicResolvers: [any DynamicScanTargetResolving] = [
        XcodeScanTargetResolver(),
        GradleScanTargetResolver()
    ]) {
        self.dynamicResolvers = dynamicResolvers
    }

    func targets() -> [ScanTarget] {
        let resolved = ScanRuleCatalog.targets.compactMap(resolve)
            + dynamicResolvers.flatMap { $0.targets() }
        return resolved.reduce(into: [String: ScanTarget]()) { targets, target in
            targets[target.url.standardizedFileURL.path] = target
        }.map(\.value)
    }

    func protectedURLs() -> [URL] {
        ScanRuleCatalog.protectedLocations.compactMap(resolve)
    }

    private func resolve(_ rule: ScanRuleDefinition) -> ScanTarget? {
        guard let baseURL = baseURL(for: rule.base) else { return nil }
        return ScanTarget(
            url: rule.components.reduce(baseURL) { url, component in
                url.appendingPathComponent(component, isDirectory: true)
            },
            name: rule.name,
            detail: rule.detail,
            category: rule.category,
            safety: rule.safety,
            mode: rule.mode
        )
    }

    private func resolve(_ location: ProtectedLocationDefinition) -> URL? {
        guard let baseURL = baseURL(for: location.base) else { return nil }
        return location.components.reduce(baseURL) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }

    private func baseURL(for base: ScanBase) -> URL? {
        let fileManager = FileManager.default
        switch base {
        case .home:
            return fileManager.homeDirectoryForCurrentUser
        case .userLibrary:
            return fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        case .userCaches:
            return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        case .userApplicationSupport:
            return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        case .localApplications:
            return fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first
        }
    }
}

private enum ScanBase: Sendable {
    case home
    case userLibrary
    case userCaches
    case userApplicationSupport
    case localApplications
}

private struct ScanRuleDefinition: Sendable {
    let base: ScanBase
    let components: [String]
    let name: String?
    let detail: String
    let category: StorageCategory
    let safety: SafetyLevel
    let mode: ScanMode
}

private struct ProtectedLocationDefinition: Sendable {
    let base: ScanBase
    let components: [String]
}

private enum ScanRuleCatalog {
    static let targets: [ScanRuleDefinition] = [
        .init(base: .home, components: [".konan"], name: "Kotlin/Native Toolchains", detail: "Kotlin/Native compilers and platform dependencies.", category: .developer, safety: .review, mode: .item),
        .init(base: .home, components: [".rbenv"], name: "rbenv Installations", detail: "Ruby versions and packages managed by rbenv.", category: .developer, safety: .review, mode: .item),
        .init(base: .home, components: [".local", "share"], name: "Local Developer Data", detail: "Data created by command-line developer tools.", category: .developer, safety: .review, mode: .item),
        .init(base: .home, components: [".codex"], name: "Codex Local Data", detail: "Local Codex state and downloaded resources.", category: .developer, safety: .review, mode: .item),
        .init(base: .userCaches, components: [], name: nil, detail: "Temporary application data. The owning app may download or recreate it.", category: .caches, safety: .safe, mode: .children(minimumSize: 5_000_000)),
        .init(base: .home, components: [".cache"], name: nil, detail: "Rebuildable cache created by a command-line developer tool.", category: .developer, safety: .safe, mode: .children(minimumSize: 5_000_000)),
        .init(base: .userApplicationSupport, components: [], name: nil, detail: "Persistent application data. Review it in the owning app before removal.", category: .appData, safety: .analysisOnly, mode: .children(minimumSize: 100_000_000)),
        .init(base: .localApplications, components: [], name: nil, detail: "Installed application. StorageSage never uninstalls apps automatically.", category: .applications, safety: .analysisOnly, mode: .children(minimumSize: 20_000_000))
    ]

    static let protectedLocations: [ProtectedLocationDefinition] = [
        .init(base: .userLibrary, components: ["Mail"]),
        .init(base: .userLibrary, components: ["Messages"]),
        .init(base: .home, components: [".Trash"])
    ]
}
