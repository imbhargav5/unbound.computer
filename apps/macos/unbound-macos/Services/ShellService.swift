//
//  ShellService.swift
//  unbound-macos
//
//  Low-level Process wrapper for executing shell commands.
//  Uses non-blocking terminationHandler instead of waitUntilExit().
//

import Foundation

// MARK: - Process Output

struct ProcessOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

// MARK: - Process Error

enum ProcessError: Error, LocalizedError, Sendable {
    case commandNotFound(String)
    case executionFailed(String, Int32)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        case .executionFailed(let message, let code):
            return "Execution failed (exit code \(code)): \(message)"
        case .timeout:
            return "Process timed out"
        case .cancelled:
            return "Process was cancelled"
        }
    }
}

// MARK: - Shell Service

@Observable
class ShellService {
    private var runningProcesses: [UUID: Process] = [:]

    /// Execute a command and return the result (non-blocking).
    /// Uses terminationHandler instead of waitUntilExit() to avoid blocking threads.
    func execute(
        _ command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        let processId = UUID()

        // Create the execution task
        let executeTask: () async throws -> ProcessOutput = {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                // Use -l (login shell) to load user's profile and PATH (includes Homebrew, etc.)
                process.arguments = ["-l", "-c", ([command] + arguments).joined(separator: " ")]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                if let workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                }

                // Merge current environment with custom environment
                var env = ProcessInfo.processInfo.environment
                if let customEnv = environment {
                    for (key, value) in customEnv {
                        env[key] = value
                    }
                }
                process.environment = env

                // Track the process
                self.runningProcesses[processId] = process

                // Use terminationHandler instead of blocking waitUntilExit()
                process.terminationHandler = { [weak self] terminatedProcess in
                    self?.runningProcesses.removeValue(forKey: processId)

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    let output = ProcessOutput(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: terminatedProcess.terminationStatus
                    )

                    continuation.resume(returning: output)
                }

                do {
                    try process.run()
                } catch {
                    self.runningProcesses.removeValue(forKey: processId)
                    continuation.resume(throwing: ProcessError.executionFailed(error.localizedDescription, -1))
                }
            }
        }

        // If timeout specified, race against it
        if let timeout {
            return try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
                group.addTask {
                    try await executeTask()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    // Terminate the process if it's still running
                    if let process = self.runningProcesses[processId] {
                        process.terminate()
                        self.runningProcesses.removeValue(forKey: processId)
                    }
                    throw ProcessError.timeout
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } else {
            return try await executeTask()
        }
    }

    /// Execute a command with streaming output
    func executeStreaming(
        _ command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) -> (stream: AsyncThrowingStream<String, Error>, processId: UUID) {
        let processId = UUID()

        let stream = AsyncThrowingStream<String, Error> { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // Use -l (login shell) to load user's profile and PATH (includes Homebrew, etc.)
            process.arguments = ["-l", "-c", ([command] + arguments).joined(separator: " ")]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            // Merge current environment with custom environment
            var env = ProcessInfo.processInfo.environment
            if let customEnv = environment {
                for (key, value) in customEnv {
                    env[key] = value
                }
            }
            process.environment = env

            // Store process for potential cancellation
            self.runningProcesses[processId] = process

            // Handle stdout streaming
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    if let str = String(data: data, encoding: .utf8) {
                        continuation.yield(str)
                    }
                }
            }

            // Handle stderr streaming (also yield to stream)
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    if let str = String(data: data, encoding: .utf8) {
                        continuation.yield(str)
                    }
                }
            }

            // Handle process termination
            process.terminationHandler = { [weak self] process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                self?.runningProcesses.removeValue(forKey: processId)

                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ProcessError.executionFailed(
                        "Process exited with code \(process.terminationStatus)",
                        process.terminationStatus
                    ))
                }
            }

            // Handle cancellation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.terminate(processId: processId)
            }

            do {
                try process.run()
            } catch {
                self.runningProcesses.removeValue(forKey: processId)
                continuation.finish(throwing: ProcessError.executionFailed(error.localizedDescription, -1))
            }
        }

        return (stream, processId)
    }

    /// Check if a command exists in PATH (async, non-blocking).
    func commandExists(_ command: String) async -> Bool {
        do {
            let result = try await execute("which \(command)", timeout: 5.0)
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    /// Check if a command exists in PATH (synchronous fallback for compatibility).
    /// Prefer using the async version when possible.
    func commandExistsSync(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which \(command)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Terminate a running process by ID
    func terminate(processId: UUID) {
        if let process = runningProcesses[processId] {
            process.terminate()
            runningProcesses.removeValue(forKey: processId)
        }
    }

    /// Terminate all running processes
    func terminateAll() {
        for (_, process) in runningProcesses {
            process.terminate()
        }
        runningProcesses.removeAll()
    }
}
