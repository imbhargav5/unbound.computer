//
//  TerminalModels.swift
//  rocketry-macos
//
//  Terminal state and models for real shell integration
//

import Foundation

// MARK: - Terminal Line

struct TerminalLine: Identifiable, Equatable {
    let id: UUID
    let type: TerminalLineType
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), type: TerminalLineType, content: String, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
    }
}

enum TerminalLineType: Equatable {
    case command(directory: String)
    case output
    case error
    case system
}

// MARK: - Terminal State

@Observable
class TerminalState {
    var lines: [TerminalLine] = []
    var currentDirectory: String
    var isRunning: Bool = false
    var commandHistory: [String] = []
    var historyIndex: Int = -1

    private var currentProcessId: UUID?
    private weak var shellService: ShellService?

    init(workingDirectory: String? = nil, shellService: ShellService? = nil) {
        self.currentDirectory = workingDirectory ?? FileManager.default.currentDirectoryPath
        self.shellService = shellService

        // Add welcome message
        lines.append(TerminalLine(
            type: .system,
            content: "Terminal ready. Type commands below."
        ))
    }

    var currentDirectoryName: String {
        (currentDirectory as NSString).lastPathComponent
    }

    var promptDirectory: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if currentDirectory.hasPrefix(homeDir) {
            return "~" + currentDirectory.dropFirst(homeDir.count)
        }
        return currentDirectory
    }

    func setShellService(_ service: ShellService) {
        self.shellService = service
    }

    func setWorkingDirectory(_ path: String) {
        if FileManager.default.fileExists(atPath: path) {
            currentDirectory = path
        }
    }

    @MainActor
    func executeCommand(_ command: String) async {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }
        guard let shellService = shellService else {
            lines.append(TerminalLine(type: .error, content: "Shell service not available"))
            return
        }

        // Add to history
        commandHistory.append(trimmedCommand)
        historyIndex = commandHistory.count

        // Add command line to output
        lines.append(TerminalLine(
            type: .command(directory: currentDirectoryName),
            content: trimmedCommand
        ))

        // Handle built-in commands
        if trimmedCommand == "clear" {
            lines.removeAll()
            return
        }

        if trimmedCommand.hasPrefix("cd ") {
            let path = String(trimmedCommand.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            changeDirectory(path)
            return
        }

        if trimmedCommand == "cd" {
            changeDirectory("~")
            return
        }

        // Execute command with streaming
        isRunning = true

        let (stream, processId) = shellService.executeStreaming(
            trimmedCommand,
            workingDirectory: currentDirectory
        )
        currentProcessId = processId

        do {
            for try await chunk in stream {
                // Split by newlines and add each line
                let outputLines = chunk.components(separatedBy: "\n")
                for (index, line) in outputLines.enumerated() {
                    // Skip empty last line from split
                    if index == outputLines.count - 1 && line.isEmpty {
                        continue
                    }
                    if !line.isEmpty {
                        lines.append(TerminalLine(type: .output, content: line))
                    }
                }
            }
        } catch let error as ProcessError {
            switch error {
            case .executionFailed(let message, _):
                // Don't show error for non-zero exit codes if we already have output
                if !message.contains("exit code") {
                    lines.append(TerminalLine(type: .error, content: message))
                }
            default:
                lines.append(TerminalLine(type: .error, content: error.localizedDescription))
            }
        } catch {
            lines.append(TerminalLine(type: .error, content: error.localizedDescription))
        }

        isRunning = false
        currentProcessId = nil
    }

    func cancelCurrentProcess() {
        guard let processId = currentProcessId, let shellService = shellService else { return }
        shellService.terminate(processId: processId)
        isRunning = false
        currentProcessId = nil
        lines.append(TerminalLine(type: .system, content: "^C"))
    }

    func getPreviousCommand() -> String? {
        guard !commandHistory.isEmpty else { return nil }
        if historyIndex > 0 {
            historyIndex -= 1
        }
        return commandHistory[historyIndex]
    }

    func getNextCommand() -> String? {
        guard !commandHistory.isEmpty else { return nil }
        if historyIndex < commandHistory.count - 1 {
            historyIndex += 1
            return commandHistory[historyIndex]
        } else {
            historyIndex = commandHistory.count
            return ""
        }
    }

    private func changeDirectory(_ path: String) {
        var targetPath = path

        // Handle ~ for home directory
        if targetPath.hasPrefix("~") {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            targetPath = homeDir + targetPath.dropFirst()
        }

        // Handle relative paths
        if !targetPath.hasPrefix("/") {
            targetPath = (currentDirectory as NSString).appendingPathComponent(targetPath)
        }

        // Resolve . and ..
        targetPath = (targetPath as NSString).standardizingPath

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory), isDirectory.boolValue {
            currentDirectory = targetPath
        } else {
            lines.append(TerminalLine(type: .error, content: "cd: no such file or directory: \(path)"))
        }
    }
}
