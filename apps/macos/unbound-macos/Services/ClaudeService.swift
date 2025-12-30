//
//  ClaudeService.swift
//  unbound-macos
//
//  Interface with Claude CLI for chat interactions
//

import Foundation

// MARK: - Claude Error

enum ClaudeError: Error, LocalizedError {
    case notInstalled
    case processStartFailed(String)
    case processFailed(Int32, String)
    case cancelled
    case noActiveProcess

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Claude CLI is not installed. Please install it first."
        case .processStartFailed(let reason):
            return "Failed to start Claude: \(reason)"
        case .processFailed(let code, let message):
            return "Claude exited with code \(code): \(message)"
        case .cancelled:
            return "Claude operation was cancelled"
        case .noActiveProcess:
            return "No active Claude process"
        }
    }
}

// MARK: - Claude Service

@Observable
class ClaudeService {
    private let shell: ShellService
    private let parser: ClaudeOutputParser

    var isRunning: Bool = false
    private var currentProcessId: UUID?
    private var stdinPipe: Pipe?
    private var currentProcess: Process?

    init(shell: ShellService) {
        self.shell = shell
        self.parser = ClaudeOutputParser()
    }

    /// Check if Claude CLI is installed
    func isClaudeInstalled() -> Bool {
        shell.commandExists("claude")
    }

    /// Escape a string for use in shell command
    private func shellEscape(_ string: String) -> String {
        // Use single quotes and escape any single quotes in the string
        let escaped = string.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    /// Send a message to Claude CLI and stream the response
    /// - Parameters:
    ///   - message: The user's message
    ///   - workingDirectory: The directory to run Claude in (worktree path)
    ///   - claudeSessionId: The Claude session ID for conversation continuity (from previous response)
    ///   - modelIdentifier: The model identifier to use (nil for default)
    func sendMessage(
        _ message: String,
        workingDirectory: String,
        claudeSessionId: String? = nil,
        modelIdentifier: String? = nil
    ) -> AsyncThrowingStream<ClaudeOutput, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isClaudeInstalled() else {
                        continuation.finish(throwing: ClaudeError.notInstalled)
                        return
                    }

                    await MainActor.run {
                        self.isRunning = true
                        self.parser.reset()
                    }

                    // Start Claude process
                    let process = Process()
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()

                    // Escape message for shell and pass as argument
                    let escapedMessage = self.shellEscape(message)

                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    // Use login shell to load user's PATH (includes Homebrew, ~/.local/bin, etc.)
                    // -p (print mode) takes prompt as argument and skips workspace trust dialog
                    // --output-format stream-json for structured JSON output (NDJSON)
                    // --verbose is required when using stream-json with -p
                    // -r (resume) with session ID for continuing conversations
                    // --model to specify which Claude model to use
                    let modelFlag = modelIdentifier.map { " --model \($0)" } ?? ""
                    let resumeFlag = claudeSessionId.map { " -r \($0)" } ?? ""
                    let claudeCmd = "claude -p --verbose --output-format stream-json\(modelFlag)\(resumeFlag) \(escapedMessage)"

                    process.arguments = ["-l", "-c", claudeCmd]
                    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    process.environment = ProcessInfo.processInfo.environment

                    self.currentProcess = process
                    let processId = UUID()
                    self.currentProcessId = processId

                    // Buffer for incomplete JSON lines
                    var lineBuffer = ""

                    // Handle stdout streaming (NDJSON - one JSON object per line)
                    stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }

                        if let text = String(data: data, encoding: .utf8) {
                            lineBuffer += text

                            // Process complete lines
                            while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                                let line = String(lineBuffer[..<newlineIndex])
                                lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])

                                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                                guard !trimmedLine.isEmpty else { continue }

                                // Parse JSON line
                                if let output = self?.parseJSONLine(trimmedLine) {
                                    continuation.yield(output)
                                }
                            }
                        }
                    }

                    // Handle stderr
                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }

                        if let text = String(data: data, encoding: .utf8) {
                            // Ignore ANSI escape sequences and empty stderr
                            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty && !cleaned.hasPrefix("\u{1B}[") {
                                continuation.yield(.error(text))
                            }
                        }
                    }

                    // Handle termination
                    process.terminationHandler = { [weak self] process in
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil

                        Task { @MainActor in
                            self?.isRunning = false
                            self?.currentProcess = nil
                            self?.stdinPipe = nil
                            self?.currentProcessId = nil
                        }

                        if process.terminationStatus == 0 {
                            continuation.yield(.complete)
                            continuation.finish()
                        } else {
                            continuation.finish(throwing: ClaudeError.processFailed(
                                process.terminationStatus,
                                "Process exited with non-zero status"
                            ))
                        }
                    }

                    // Handle cancellation
                    continuation.onTermination = { @Sendable [weak self] _ in
                        self?.cancel()
                    }

                    // Start the process
                    do {
                        try process.run()
                    } catch {
                        await MainActor.run {
                            self.isRunning = false
                            self.currentProcess = nil
                        }
                        continuation.finish(throwing: ClaudeError.processStartFailed(error.localizedDescription))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse a single JSON line from stream-json output
    private func parseJSONLine(_ line: String) -> ClaudeOutput? {
        guard let data = line.data(using: .utf8) else { return nil }

        do {
            let message = try JSONDecoder().decode(ClaudeJSONMessage.self, from: data)
            return convertJSONMessage(message)
        } catch {
            // If JSON parsing fails, treat as raw text
            return .text(line)
        }
    }

    /// Convert a ClaudeJSONMessage to ClaudeOutput
    private func convertJSONMessage(_ message: ClaudeJSONMessage) -> ClaudeOutput? {
        switch message.type {
        case "system":
            // System messages include session_id on init
            if message.subtype == "init", let sessionId = message.sessionId {
                return .sessionStarted(sessionId)
            }
            return nil

        case "assistant":
            // Assistant message with content blocks
            if let contentBlocks = message.message?.content {
                // Extract text from content blocks
                let textParts = contentBlocks.compactMap { block -> String? in
                    if block.type == "text" {
                        return block.text
                    }
                    return nil
                }
                if !textParts.isEmpty {
                    return .text(textParts.joined())
                }

                // Handle tool use blocks
                for block in contentBlocks {
                    if block.type == "tool_use", let name = block.name {
                        let toolUse = ToolUse(
                            toolUseId: block.toolUseId,
                            toolName: name,
                            input: block.input?.jsonString,
                            status: .running
                        )
                        return .structuredBlock(.toolUse(toolUse))
                    }
                }
            }
            return nil

        case "user":
            // User messages (tool results)
            if let contentBlocks = message.message?.content {
                for block in contentBlocks {
                    if block.type == "tool_result",
                       let toolUseId = block.toolUseId,
                       let content = block.content {
                        // Emit tool result to update the matching tool
                        return .toolResult(toolUseId: toolUseId, output: content)
                    }
                }
            }
            return nil

        case "result":
            // Final result message
            if let resultContent = message.result?.content {
                let textParts = resultContent.compactMap { block -> String? in
                    if block.type == "text" {
                        return block.text
                    }
                    return nil
                }
                if !textParts.isEmpty {
                    return .text(textParts.joined())
                }
            }

            // Check for errors
            if message.isError == true, let content = message.content {
                return .error(content)
            }

            return nil

        default:
            return nil
        }
    }

    /// Send a response to an interactive prompt
    func respondToPrompt(_ response: String) throws {
        guard let stdinPipe = stdinPipe else {
            throw ClaudeError.noActiveProcess
        }

        if let data = (response + "\n").data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
    }

    /// Cancel the current operation
    func cancel() {
        currentProcess?.terminate()
        isRunning = false
        currentProcess = nil
        stdinPipe = nil
        currentProcessId = nil
    }
}
