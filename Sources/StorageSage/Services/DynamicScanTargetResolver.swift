//
//  DynamicScanTargetResolver.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol DynamicScanTargetResolving: Sendable {
    func targets() -> [ScanTarget]
}

struct XcodeScanTargetResolver: DynamicScanTargetResolving {
    private let commands: any CommandRunning

    init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    func targets() -> [ScanTarget] {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return []
        }
        let developerRoot = ["Developer", "Xcode"].reduce(library) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        let derivedData = customDerivedDataURL()
            ?? developerRoot.appendingPathComponent("DerivedData", isDirectory: true)

        return [
            ScanTarget(url: derivedData, name: "Xcode Derived Data", detail: "Build products and indexes. Xcode recreates them when needed.", category: .xcode, safety: .safe, mode: .item),
            ScanTarget(url: ["UserData", "Previews"].reduce(developerRoot) { $0.appendingPathComponent($1, isDirectory: true) }, name: "SwiftUI Preview Data", detail: "Generated preview content that Xcode can rebuild.", category: .xcode, safety: .safe, mode: .item),
            ScanTarget(url: developerRoot.appendingPathComponent("iOS DeviceSupport", isDirectory: true), name: "iOS Device Support", detail: "Debug symbols for connected iOS versions. They are downloaded again when required.", category: .xcode, safety: .review, mode: .item)
        ]
    }

    private func customDerivedDataURL() -> URL? {
        guard
            let result = commands.run(
                "defaults",
                arguments: ["read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"],
                timeout: 2
            ),
            result.terminationStatus == 0,
            let rawValue = String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty,
            rawValue.caseInsensitiveCompare("Default") != .orderedSame
        else { return nil }

        let expanded = NSString(string: rawValue).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
}

struct GradleScanTargetResolver: DynamicScanTargetResolving {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func targets() -> [ScanTarget] {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gradle", isDirectory: true)
        let root: URL
        if let configured = environment["GRADLE_USER_HOME"], configured.hasPrefix("/") {
            root = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        } else {
            root = fallback
        }

        return [
            ScanTarget(url: root.appendingPathComponent("caches", isDirectory: true), name: "Gradle Caches", detail: "Downloaded and generated Gradle artifacts.", category: .developer, safety: .safe, mode: .item),
            ScanTarget(url: root.appendingPathComponent("daemon", isDirectory: true), name: "Gradle Daemon Data", detail: "Logs and state from Gradle daemon processes.", category: .developer, safety: .safe, mode: .item),
            ScanTarget(url: root.appendingPathComponent("jdks", isDirectory: true), name: "Gradle-managed JDKs", detail: "JDK installations downloaded and managed by Gradle.", category: .developer, safety: .review, mode: .item)
        ]
    }
}
