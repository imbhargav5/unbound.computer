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
        // First check known paths synchronously (fast file system check)
        for path in daemonPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                return expandedPath
            }
        }

        // Try which command as fallback (async to avoid blocking)
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

    // MARK: - Launch Methods

    /// Ensure the daemon is running, starting it if necessary.
    static func ensureDaemonRunning() async throws {
        // Check if already running (quick socket file check)
        if DaemonClient.shared.isDaemonRunning() {
            logger.info("Daemon socket exists, assuming running")
            return
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
        process.arguments = ["start", "--background"]
        var environment = ProcessInfo.processInfo.environment
        if let heartbeatURL = Config.presenceDOHeartbeatURL {
            environment["UNBOUND_PRESENCE_DO_HEARTBEAT_URL"] = heartbeatURL
        }
        if let token = Config.presenceDOToken {
            environment["UNBOUND_PRESENCE_DO_TOKEN"] = token
        }
        environment["UNBOUND_PRESENCE_DO_TTL_MS"] = String(Config.presenceDOTTLMS)
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
