//
//  FSEventsMonitor.swift
//  StorageSage
//
//  Created by Stefan Boblic on 10.08.2026.
//

import CoreServices
import Foundation

struct FileChangeBatch: Equatable, Sendable {
    let paths: [String]
    let requiresFullRescan: Bool

    func affects(_ roots: [URL]) -> Bool {
        paths.contains { changedPath in
            roots.contains { root in
                let rootPath = root.standardizedFileURL.path
                return changedPath == rootPath
                    || changedPath.hasPrefix(rootPath + "/")
                    || rootPath.hasPrefix(changedPath + "/")
            }
        }
    }
}

final class FSEventsMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var revision = 0
    @Published private(set) var latestBatch = FileChangeBatch(paths: [], requiresFullRescan: false)

    private let roots: [URL]
    private let eventIDDefaultsKey = "filesystem.lastEventID"
    private let callbackQueue = DispatchQueue(label: "com.storagesage.filesystem-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private var callbackBox: FSEventsCallbackBox?

    init(roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser]) {
        self.roots = roots
    }

    func start() {
        guard stream == nil, !roots.isEmpty else { return }
        let box = FSEventsCallbackBox { [weak self] paths, flags, eventIDs in
            self?.receive(paths: paths, flags: flags, eventIDs: eventIDs)
        }
        callbackBox = box
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let storedID = UInt64(UserDefaults.standard.object(forKey: eventIDDefaultsKey) as? Int64 ?? 0)
        let sinceWhen = storedID > 0 ? storedID : FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        let paths = roots.map(\.path) as CFArray
        stream = FSEventStreamCreate(
            nil,
            Self.callback,
            &context,
            paths,
            sinceWhen,
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        callbackBox = nil
    }

    deinit {
        stop()
    }

    private func receive(
        paths: [String],
        flags: [FSEventStreamEventFlags],
        eventIDs: [FSEventStreamEventId]
    ) {
        if let latestID = eventIDs.max() {
            UserDefaults.standard.set(Int64(bitPattern: latestID), forKey: eventIDDefaultsKey)
        }
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        let batch = FileChangeBatch(
            paths: Array(Set(paths)).sorted(),
            requiresFullRescan: flags.contains { $0 & rescanFlags != 0 }
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestBatch = batch
            self.revision &+= 1
        }
    }

    private static let callback: FSEventStreamCallback = {
        _, contextInfo, eventCount, eventPathsPointer, eventFlags, eventIDs in
        guard let contextInfo else { return }
        let box = Unmanaged<FSEventsCallbackBox>.fromOpaque(contextInfo).takeUnretainedValue()
        let paths = unsafeBitCast(eventPathsPointer, to: NSArray.self) as? [String] ?? []
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: eventCount))
        let ids = Array(UnsafeBufferPointer(start: eventIDs, count: eventCount))
        box.handler(paths, flags, ids)
    }
}

private final class FSEventsCallbackBox {
    let handler: ([String], [FSEventStreamEventFlags], [FSEventStreamEventId]) -> Void

    init(handler: @escaping ([String], [FSEventStreamEventFlags], [FSEventStreamEventId]) -> Void) {
        self.handler = handler
    }
}
