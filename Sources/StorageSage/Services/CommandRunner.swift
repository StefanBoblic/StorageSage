//
//  CommandRunner.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation

struct CommandResult: Sendable {
    let output: Data
    let errorOutput: Data
    let terminationStatus: Int32
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult?
}

struct CommandRunner: CommandRunning {
    private let executables: any ExecutableLocating

    init(executables: any ExecutableLocating = PathExecutableLocator()) {
        self.executables = executables
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult? {
        guard let executableURL = executables.locate(executable) else { return nil }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
            let outputReader = PipeReader(handle: outputPipe.fileHandleForReading)
            let errorReader = PipeReader(handle: errorPipe.fileHandleForReading)
            outputReader.start()
            errorReader.start()
            if completion.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if completion.wait(timeout: .now() + 1) == .timedOut {
                    process.interrupt()
                    _ = completion.wait(timeout: .now() + 1)
                }
                outputReader.stop()
                errorReader.stop()
                return nil
            }
            return CommandResult(
                output: outputReader.finish(),
                errorOutput: errorReader.finish(),
                terminationStatus: process.terminationStatus
            )
        } catch {
            return nil
        }
    }
}

private final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "com.storagesage.pipe-reader", qos: .utility)
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        queue.async { [self] in
            let result = handle.readDataToEndOfFile()
            lock.lock()
            data = result
            lock.unlock()
            completion.signal()
        }
    }

    func finish() -> Data {
        completion.wait()
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func stop() {
        try? handle.close()
        _ = completion.wait(timeout: .now() + 1)
    }
}
