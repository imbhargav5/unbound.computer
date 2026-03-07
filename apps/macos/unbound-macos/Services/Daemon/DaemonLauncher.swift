//
//  DaemonLauncher.swift
//  unbound-macos
//
//  Service for launching and managing the Unbound daemon lifecycle.
//  Ensures the daemon is running before the app tries to connect.
//  Uses async process execution to avoid blocking the main thread.
//

import Foundation
import Logging

private let logger = Logger(label: "app.daemon.launcher")

// MARK: - Daemon Launcher

/// Service for launching and managing the Unbound daemon.
enum DaemonLauncher {
    // MARK: - Daemon Binary Paths

    /// Possible locations for the daemon binary.
    private static let daemonPaths = [
        "/usr/local/bin/unbound-daemon",
        "/opt/homebrew/bin/unbound-daemon",
        "~/.cargo/bin/unbound-daemon",
        "~/.local/bin/unbound-daemon",
        // Also check for daemon-bin (the actual crate name)
        "/usr/local/bin/daemon-bin",
        "/opt/homebrew/bin/daemon-bin",
        "~/.cargo/bin/daemon-bin"
    ]

    /// Find the daemon binary path (async, non-blocking).
    private static func findDaemonBinary() async -> String? {
        // 1. Check bundled binary first (inside app bundle)
        if let bundledPath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("unbound-daemon")
            .path,
           FileManager.default.isExecutableFile(atPath: bundledPath)
        {
            logger.info("Found bundled daemon binary")
            return bundledPath
        }

        // 2. Fall back to known system paths
        for path in daemonPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                return expandedPath
            }
        }

        // 3. Try which command as last resort (async to avoid blocking)
        return await findDaemonBinaryViaWhich()
    }

    /// Use `which` command to find daemon binary (async, non-blocking).
    private static func findDaemonBinaryViaWhich() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["unbound-daemon"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            // Use terminationHandler instead of blocking waitUntilExit()
            process.terminationHandler = { terminatedProcess in
                if terminatedProcess.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !path.isEmpty {
                        continuation.resume(returning: path)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }

            do {
                try process.run()
            } catch {
                logger.debug("which command failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - .env Loading

    /// Load a `.env.local` file into the environment dictionary.
    /// Searches next to the daemon binary, then walks up to find `apps/daemon/.env.local`.
    private static func loadDotEnv(into environment: inout [String: String], daemonPath: String) {
        let candidates = dotEnvCandidates(daemonPath: daemonPath)

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate),
                  let contents = try? String(contentsOfFile: candidate, encoding: .utf8) else {
                continue
            }

            logger.info("Loading env from \(candidate)")
            var count = 0
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

                guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[trimmed.startIndex..<equalsIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalsIndex)...])
                    .trimmingCharacters(in: .whitespaces)

                guard !key.isEmpty else { continue }
                // Don't override values already set in the process environment
                if environment[key] == nil {
                    environment[key] = value
                    count += 1
                }
            }
            logger.info("Loaded \(count) env vars from .env.local")
            return
        }

        logger.debug("No .env.local found for daemon")
    }

    /// Resolve the repo root using this Swift source file's compile-time path,
    /// then return `apps/daemon/.env.local` within the repo.
    private static func dotEnvCandidates(daemonPath: String, sourceFile: String = #file) -> [String] {
        var candidates: [String] = []

        // Primary: derive repo root from this source file's compile-time path.
        // This file is at <repo>/apps/macos/unbound-macos/Services/Daemon/DaemonLauncher.swift
        // so repo root is 5 directories up.
        var dir = (sourceFile as NSString).deletingLastPathComponent
        for _ in 0..<5 {
            dir = (dir as NSString).deletingLastPathComponent
        }
        let repoCandidate = (dir as NSString).appendingPathComponent("apps/daemon/.env.local")
        candidates.append(repoCandidate)

        // Fallback: next to the daemon binary
        let binaryDir = (daemonPath as NSString).deletingLastPathComponent
        candidates.append((binaryDir as NSString).appendingPathComponent(".env.local"))

        return candidates
    }

    // MARK: - CLI Symlink

    /// Install a symlink to the bundled daemon binary so it's accessible from the terminal.
    /// Creates `~/.local/bin/unbound-daemon` → bundled binary in app bundle.
    static func installCLISymlink() {
        guard let bundledPath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("unbound-daemon")
            .path,
              FileManager.default.isExecutableFile(atPath: bundledPath)
        else {
            logger.debug("No bundled daemon binary found, skipping symlink install")
            return
        }

        let binDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin")
        let symlinkPath = binDir.appendingPathComponent("unbound-daemon").path

        // Create ~/.local/bin if needed
        if !FileManager.default.fileExists(atPath: binDir.path) {
            do {
                try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            } catch {
                logger.warning("Could not create ~/.local/bin: \(error)")
                return
            }
        }

        // Remove existing file/symlink at destination
        if FileManager.default.fileExists(atPath: symlinkPath) {
            // If it's already a symlink pointing to the right place, nothing to do
            if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath),
               dest == bundledPath
            {
                return
            }
            do {
                try FileManager.default.removeItem(atPath: symlinkPath)
            } catch {
                logger.warning("Could not remove existing file at \(symlinkPath): \(error)")
                return
            }
        }

        do {
            try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: bundledPath)
            logger.info("Installed CLI symlink: \(symlinkPath) → \(bundledPath)")
        } catch {
            logger.warning("Could not create CLI symlink: \(error)")
        }
    }

    // MARK: - Launch Methods

    /// Ensure the daemon is running, starting it if necessary.
    static func ensureDaemonRunning() async throws {
        // Verify the daemon is actually responsive, not just that the socket file exists.
        // A stale socket file can remain after the process is killed.
        if await DaemonClient.shared.isDaemonAlive() {
            logger.info("Daemon is alive and responsive")
            return
        }

        #if DEBUG
        // In debug builds, expect the daemon to be started manually (e.g. cargo run).
        // Wait for it instead of trying to find and launch a binary.
        logger.info("DEBUG: Waiting for externally-managed daemon...")
        try await waitForDaemon(timeout: 30.0)
        return
        #endif

        // Clean up stale socket if it exists but nothing is listening
        let socketPath = DaemonClient.defaultSocketPath
        if FileManager.default.fileExists(atPath: socketPath) {
            logger.info("Removing stale daemon socket")
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        logger.info("Daemon not running, attempting to start")

        // Find daemon binary (async to avoid blocking)
        guard let daemonPath = await findDaemonBinary() else {
            logger.error("Could not find unbound-daemon binary")
            throw DaemonLauncherError.binaryNotFound
        }

        logger.info("Found daemon binary at \(daemonPath)")

        // Start daemon
        try await startDaemon(at: daemonPath)

        // Wait for socket to appear
        try await waitForDaemon()
    }

    /// Start the daemon process.
    private static func startDaemon(at path: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["start", "--base-dir", Config.daemonBaseDir]

        // Start from a clean slate — only pass what the daemon needs.
        // ProcessInfo.processInfo.environment can contain stale or empty values
        // that prevent loadDotEnv from setting keys (it skips non-nil entries).
        var environment: [String: String] = [:]

        #if DEBUG
        // Load .env.local first so all dev config (OTEL, Groq, etc.) is available.
        loadDotEnv(into: &environment, daemonPath: path)
        #endif

        // Authoritative config from the macOS app — always overrides .env.local.
        environment["SUPABASE_URL"] = Config.supabaseURL.absoluteString
        environment["SUPABASE_PUBLISHABLE_KEY"] = Config.supabasePublishableKey
        environment["UNBOUND_WEB_APP_URL"] = Config.apiURL.absoluteString

        if let heartbeatURL = Config.presenceDOHeartbeatURL {
            environment["UNBOUND_PRESENCE_DO_HEARTBEAT_URL"] = heartbeatURL
        }
        if let token = Config.presenceDOToken {
            environment["UNBOUND_PRESENCE_DO_TOKEN"] = token
        }
        environment["UNBOUND_PRESENCE_DO_TTL_MS"] = String(Config.presenceDOTTLMS)

        // Carry over PATH so the daemon can find system tools.
        if let systemPath = ProcessInfo.processInfo.environment["PATH"] {
            environment["PATH"] = systemPath
        }
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            environment["HOME"] = home
        }

        process.environment = environment

        // Detach from parent
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            logger.info("Started daemon process")
        } catch {
            logger.error("Failed to start daemon: \(error)")
            throw DaemonLauncherError.launchFailed(error.localizedDescription)
        }
    }

    /// Wait for the daemon socket to appear.
    private static func waitForDaemon(timeout: TimeInterval = 10.0) async throws {
        let startTime = Date()
        let pollInterval: TimeInterval = 0.25

        while Date().timeIntervalSince(startTime) < timeout {
            if DaemonClient.shared.isDaemonRunning() {
                logger.info("Daemon socket is ready")
                return
            }

            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        logger.error("Timeout waiting for daemon socket")
        throw DaemonLauncherError.startupTimeout
    }

    /// Stop the daemon.
    static func stopDaemon() async throws {
        do {
            _ = try await DaemonClient.shared.call(method: .shutdown)
            logger.info("Daemon shutdown requested")
        } catch {
            // Daemon might already be stopped
            logger.warning("Could not send shutdown request: \(error)")
        }
    }

    /// Check if daemon is installed (async).
    static func isDaemonInstalled() async -> Bool {
        await findDaemonBinary() != nil
    }

    /// Check if daemon is installed (sync, only checks known paths).
    /// For a complete check including PATH lookup, use the async version.
    static func isDaemonInstalledSync() -> Bool {
        // Check bundled binary first
        if let bundledPath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("unbound-daemon")
            .path,
           FileManager.default.isExecutableFile(atPath: bundledPath)
        {
            return true
        }

        for path in daemonPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                return true
            }
        }
        return false
    }
}

// MARK: - Errors

enum DaemonLauncherError: LocalizedError {
    case binaryNotFound
    case launchFailed(String)
    case startupTimeout

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Unbound daemon binary not found. Please install it first."
        case .launchFailed(let reason):
            return "Failed to launch daemon: \(reason)"
        case .startupTimeout:
            return "Daemon did not start within the expected time."
        }
    }
}
