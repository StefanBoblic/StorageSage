//
//  SimulatorStorageAnalyzer.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

protocol StorageAnalyzing: Sendable {
    func analyze() -> [CleanupCandidate]
}

protocol SimulatorDeviceLocationProviding: Sendable {
    func devicesURL() -> URL?
}

struct DefaultSimulatorDeviceLocationProvider: SimulatorDeviceLocationProviding {
    func devicesURL() -> URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return ["Developer", "CoreSimulator", "Devices"].reduce(library) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }
}

struct SimulatorStorageAnalyzer: StorageAnalyzing {
    private let locations: any SimulatorDeviceLocationProviding
    private let fileSystem: any FileSystemInspecting
    private let executables: any ExecutableLocating

    init(
        locations: any SimulatorDeviceLocationProviding = DefaultSimulatorDeviceLocationProvider(),
        fileSystem: any FileSystemInspecting = FileSystemInspector(),
        executables: any ExecutableLocating = PathExecutableLocator()
    ) {
        self.locations = locations
        self.fileSystem = fileSystem
        self.executables = executables
    }

    func analyze() -> [CleanupCandidate] {
        guard
            let devicesURL = locations.devicesURL(),
            let devices = try? fileSystem.children(of: devicesURL),
            let installedRuntimes = installedRuntimeIdentifiers(),
            !installedRuntimes.isEmpty
        else { return [] }

        var orphanedSize: Int64 = 0
        var orphanedCount = 0

        for device in devices {
            let propertyListURL = device.appendingPathComponent("device.plist", isDirectory: false)
            guard
                let data = try? Data(contentsOf: propertyListURL),
                let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let dictionary = object as? [String: Any],
                let runtime = dictionary["runtime"] as? String,
                !installedRuntimes.contains(runtime)
            else { continue }

            orphanedCount += 1
            orphanedSize += fileSystem.allocatedSize(of: device)
        }

        guard orphanedCount > 0 else { return [] }
        return [CleanupCandidate(
            id: "orphaned-simulators",
            name: "Unavailable Simulator Devices",
            detail: "\(orphanedCount) devices belong to iOS runtimes that are no longer installed.",
            path: devicesURL.path,
            category: .simulators,
            safety: .safe,
            strategy: .deleteUnavailableSimulators,
            size: orphanedSize,
            modifiedAt: fileSystem.modificationDate(of: devicesURL)
        )]
    }

    private func installedRuntimeIdentifiers() -> Set<String>? {
        guard let xcrun = executables.locate("xcrun") else { return nil }

        let process = Process()
        process.executableURL = xcrun
        process.arguments = ["simctl", "list", "runtimes", "--json"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let runtimes = json["runtimes"] as? [[String: Any]]
            else { return nil }

            return Set(runtimes.compactMap { runtime in
                guard (runtime["isAvailable"] as? Bool) != false else { return nil }
                return runtime["identifier"] as? String
            })
        } catch {
            return nil
        }
    }
}
