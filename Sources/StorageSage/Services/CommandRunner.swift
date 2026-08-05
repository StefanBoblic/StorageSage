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
            if completion.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                _ = completion.wait(timeout: .now() + 1)
                return nil
            }
            return CommandResult(
                output: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                errorOutput: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                terminationStatus: process.terminationStatus
            )
        } catch {
            return nil
        }
    }
}
