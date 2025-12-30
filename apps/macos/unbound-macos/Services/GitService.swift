//
//  GitService.swift
//  unbound-macos
//
//  Git operations including worktree management
//

import Foundation

// MARK: - Git Status

struct GitStatus {
    let branch: String
    let isClean: Bool
    let staged: [String]
    let modified: [String]
    let untracked: [String]
}

// MARK: - Git Error

enum GitError: Error, LocalizedError {
    case notARepository
    case worktreeAlreadyExists(String)
    case worktreeCreationFailed(String)
    case worktreeRemovalFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "Not a git repository"
        case .worktreeAlreadyExists(let path):
            return "Worktree already exists at: \(path)"
        case .worktreeCreationFailed(let reason):
            return "Failed to create worktree: \(reason)"
        case .worktreeRemovalFailed(let reason):
            return "Failed to remove worktree: \(reason)"
        case .commandFailed(let reason):
            return "Git command failed: \(reason)"
        }
    }
}

// MARK: - Git Service

@Observable
class GitService {
    private let shell: ShellService

    init(shell: ShellService) {
        self.shell = shell
    }

    /// Check if a path is a git repository
    func isGitRepository(at path: String) async -> Bool {
        do {
            let result = try await shell.execute(
                "git rev-parse --is-inside-work-tree",
                workingDirectory: path
            )
            return result.exitCode == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    /// Get the root directory of a git repository
    func repositoryRoot(at path: String) async throws -> String {
        let result = try await shell.execute(
            "git rev-parse --show-toplevel",
            workingDirectory: path
        )

        guard result.exitCode == 0 else {
            throw GitError.notARepository
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the current branch name
    func currentBranch(at path: String) async throws -> String {
        let result = try await shell.execute(
            "git branch --show-current",
            workingDirectory: path
        )

        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr)
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the default branch name (main or master)
    func defaultBranch(at path: String) async throws -> String {
        // Try to get from remote
        let remoteResult = try await shell.execute(
            "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'",
            workingDirectory: path
        )

        if remoteResult.exitCode == 0 && !remoteResult.stdout.isEmpty {
            return remoteResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fall back to checking if main or master exists
        let mainResult = try await shell.execute(
            "git rev-parse --verify main 2>/dev/null",
            workingDirectory: path
        )

        if mainResult.exitCode == 0 {
            return "main"
        }

        return "master"
    }

    /// Create a git worktree
    func createWorktree(
        source: String,
        destination: String,
        branch: String? = nil
    ) async throws {
        // Ensure destination parent directory exists
        let destinationURL = URL(fileURLWithPath: destination)
        let parentDir = destinationURL.deletingLastPathComponent().path

        let mkdirResult = try await shell.execute("mkdir -p '\(parentDir)'")
        guard mkdirResult.exitCode == 0 else {
            throw GitError.worktreeCreationFailed("Failed to create parent directory")
        }

        // Create worktree
        var command = "git worktree add '\(destination)'"

        if let branch = branch {
            // Create new branch from current HEAD
            command += " -b '\(branch)'"
        }

        let result = try await shell.execute(command, workingDirectory: source)

        guard result.exitCode == 0 else {
            if result.stderr.contains("already exists") {
                throw GitError.worktreeAlreadyExists(destination)
            }
            throw GitError.worktreeCreationFailed(result.stderr)
        }
    }

    /// Remove a git worktree
    func removeWorktree(at path: String) async throws {
        // First, get the main repository path
        let result = try await shell.execute(
            "git worktree remove '\(path)' --force"
        )

        guard result.exitCode == 0 else {
            throw GitError.worktreeRemovalFailed(result.stderr)
        }
    }

    /// List all worktrees for a repository
    func listWorktrees(at path: String) async throws -> [String] {
        let result = try await shell.execute(
            "git worktree list --porcelain",
            workingDirectory: path
        )

        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr)
        }

        // Parse porcelain output
        var worktrees: [String] = []
        let lines = result.stdout.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("worktree ") {
                let path = String(line.dropFirst("worktree ".count))
                worktrees.append(path)
            }
        }

        return worktrees
    }

    /// Get repository status
    func status(at path: String) async throws -> GitStatus {
        // Get current branch
        let branch = try await currentBranch(at: path)

        // Get status
        let result = try await shell.execute(
            "git status --porcelain",
            workingDirectory: path
        )

        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr)
        }

        var staged: [String] = []
        var modified: [String] = []
        var untracked: [String] = []

        let lines = result.stdout.components(separatedBy: "\n")

        for line in lines where !line.isEmpty {
            let indexStatus = line.prefix(1)
            let workTreeStatus = line.dropFirst().prefix(1)
            let filename = String(line.dropFirst(3))

            if indexStatus != " " && indexStatus != "?" {
                staged.append(filename)
            }

            if workTreeStatus == "M" {
                modified.append(filename)
            }

            if indexStatus == "?" {
                untracked.append(filename)
            }
        }

        return GitStatus(
            branch: branch,
            isClean: staged.isEmpty && modified.isEmpty && untracked.isEmpty,
            staged: staged,
            modified: modified,
            untracked: untracked
        )
    }

    /// Fetch from remote
    func fetch(at path: String) async throws {
        let result = try await shell.execute(
            "git fetch --all",
            workingDirectory: path
        )

        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr)
        }
    }
}
