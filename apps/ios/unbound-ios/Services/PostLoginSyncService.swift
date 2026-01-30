//
//  PostLoginSyncService.swift
//  unbound-ios
//
//  Service to sync data from Supabase after user login.
//  iOS pulls repositories, sessions, and session state from Supabase into local SQLite.
//

import Foundation
import Logging
import UIKit
import Supabase

private let logger = Logger(label: "app.sync")

// MARK: - Supabase Response Models

/// Model for fetching repositories from Supabase
private struct SupabaseRepositoryResponse: Codable {
    let id: String
    let userId: String
    let deviceId: String
    let name: String
    let localPath: String
    let remoteUrl: String?
    let defaultBranch: String?
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceId = "device_id"
        case name
        case localPath = "local_path"
        case remoteUrl = "remote_url"
        case defaultBranch = "default_branch"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Model for fetching sessions from Supabase
private struct SupabaseSessionResponse: Codable {
    let id: String
    let userId: String
    let deviceId: String
    let repositoryId: String
    let status: String
    let sessionStartedAt: String
    let lastHeartbeatAt: String?
    let isWorktree: Bool
    let worktreePath: String?
    let workingDirectory: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceId = "device_id"
        case repositoryId = "repository_id"
        case status
        case sessionStartedAt = "session_started_at"
        case lastHeartbeatAt = "last_heartbeat_at"
        case isWorktree = "is_worktree"
        case worktreePath = "worktree_path"
        case workingDirectory = "working_directory"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Model for fetching devices from Supabase
private struct SupabaseDeviceResponse: Codable {
    let id: String
    let userId: String
    let name: String
    let deviceType: String
    let hostname: String?
    let isActive: Bool
    let lastSeenAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case deviceType = "device_type"
        case hostname
        case isActive = "is_active"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Service to sync data from Supabase after login
@Observable
final class PostLoginSyncService {
    // MARK: - Properties

    private let authService: AuthService
    private let deviceTrustService: DeviceTrustService
    private let databaseService: DatabaseService
    private let syncedDataService: SyncedDataService

    private(set) var isSyncing = false
    private(set) var syncError: Error?
    private(set) var syncProgress: Double = 0.0
    private(set) var syncMessage: String = ""

    // MARK: - Initialization

    init(
        authService: AuthService = .shared,
        deviceTrustService: DeviceTrustService = .shared,
        databaseService: DatabaseService = .shared,
        syncedDataService: SyncedDataService = .shared
    ) {
        self.authService = authService
        self.deviceTrustService = deviceTrustService
        self.databaseService = databaseService
        self.syncedDataService = syncedDataService
    }

    // MARK: - Public API

    /// Called when entering main area post-login
    /// iOS pulls devices, repositories, sessions from Supabase
    func performPostLoginSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncProgress = 0.0
        syncMessage = "Starting sync..."

        do {
            // Step 1: Ensure device is registered with all details
            syncProgress = 0.1
            syncMessage = "Registering device..."
            await syncDevice()

            // Step 2: Fetch devices from Supabase (for device list UI)
            syncProgress = 0.2
            syncMessage = "Syncing devices..."
            await syncDevicesFromSupabase()

            // Step 3: Fetch and sync repositories from Supabase to SQLite
            syncProgress = 0.4
            syncMessage = "Syncing repositories..."
            await syncRepositoriesFromSupabase()

            // Step 4: Fetch and sync sessions from Supabase to SQLite
            syncProgress = 0.7
            syncMessage = "Syncing sessions..."
            await syncSessionsFromSupabase()

            syncProgress = 1.0
            syncMessage = "Sync complete"
            logger.info("iOS sync completed successfully")
        } catch {
            syncError = error
            syncMessage = "Sync failed"
            logger.error("iOS sync failed: \(error)")
        }

        isSyncing = false
    }

    // MARK: - Device Sync

    /// Upsert device details to Supabase
    private func syncDevice() async {
        // Device registration is handled by AuthService.registerDevice()
        // This includes: device ID, name, type, hostname, APNs token, trust status
        await authService.registerDevice()
    }

    // MARK: - Devices Sync (Supabase → SyncedDataService)

    /// Fetch all user's devices from Supabase for UI display
    private func syncDevicesFromSupabase() async {
        guard let userId = authService.currentUserId else {
            logger.warning("Cannot sync devices: missing userId")
            return
        }

        do {
            // Fetch all devices for this user from Supabase
            let response = try await authService.supabaseClient
                .from("devices")
                .select()
                .eq("user_id", value: userId)
                .execute()

            let supabaseDevices = try JSONDecoder().decode([SupabaseDeviceResponse].self, from: response.data)

            logger.debug("Fetched \(supabaseDevices.count) devices from Supabase")

            // Convert to SyncedDevice models
            let syncedDevices: [SyncedDevice] = supabaseDevices.compactMap { device in
                guard let deviceId = UUID(uuidString: device.id),
                      let deviceType = SyncedDevice.DeviceType(rawValue: device.deviceType) else {
                    logger.warning("Skipping device with invalid ID or type: \(device.id), \(device.deviceType)")
                    return nil
                }

                return SyncedDevice(
                    id: deviceId,
                    name: device.name,
                    deviceType: deviceType,
                    hostname: device.hostname,
                    isActive: device.isActive,
                    lastSeenAt: device.lastSeenAt.flatMap { parseDate($0) },
                    createdAt: parseDate(device.createdAt) ?? Date()
                )
            }

            // Update SyncedDataService with devices
            syncedDataService.updateDevices(syncedDevices)

            logger.info("Synced \(syncedDevices.count) devices to SyncedDataService")
        } catch {
            logger.warning("Failed to sync devices: \(error)")
        }
    }

    // MARK: - Repositories Sync (Supabase → SQLite)

    /// Fetch repositories from Supabase and store in local SQLite
    private func syncRepositoriesFromSupabase() async {
        guard let userId = authService.currentUserId else {
            logger.warning("Cannot sync repositories: missing userId")
            return
        }

        do {
            // Fetch all repositories for this user from Supabase
            let response = try await authService.supabaseClient
                .from("repositories")
                .select()
                .eq("user_id", value: userId)
                .execute()

            let supabaseRepos = try JSONDecoder().decode([SupabaseRepositoryResponse].self, from: response.data)

            logger.debug("Fetched \(supabaseRepos.count) repositories from Supabase")

            // Upsert each repository into local SQLite
            for repo in supabaseRepos {
                let record = RepositoryRecord(
                    id: repo.id,
                    path: repo.localPath,
                    name: repo.name,
                    lastAccessedAt: parseDate(repo.updatedAt) ?? Date(),
                    addedAt: parseDate(repo.createdAt) ?? Date(),
                    isGitRepository: true,
                    sessionsPath: nil,
                    defaultBranch: repo.defaultBranch,
                    defaultRemote: repo.remoteUrl,
                    createdAt: parseDate(repo.createdAt) ?? Date(),
                    updatedAt: parseDate(repo.updatedAt) ?? Date()
                )

                try await databaseService.repositories.upsert(record)
            }

            logger.info("Synced \(supabaseRepos.count) repositories to SQLite")
        } catch {
            logger.warning("Failed to sync repositories: \(error)")
        }
    }

    // MARK: - Sessions Sync (Supabase → SQLite)

    /// Fetch sessions from Supabase and store in local SQLite
    private func syncSessionsFromSupabase() async {
        guard let userId = authService.currentUserId else {
            logger.warning("Cannot sync sessions: missing userId")
            return
        }

        do {
            // Fetch all sessions for this user from Supabase
            let response = try await authService.supabaseClient
                .from("agent_coding_sessions")
                .select()
                .eq("user_id", value: userId)
                .execute()

            let supabaseSessions = try JSONDecoder().decode([SupabaseSessionResponse].self, from: response.data)

            logger.debug("Fetched \(supabaseSessions.count) sessions from Supabase")

            // Upsert each session into local SQLite
            for session in supabaseSessions {
                let record = SessionRecord(
                    id: session.id,
                    name: "Session",  // Name is derived from repo on macOS
                    repositoryId: session.repositoryId,
                    worktreePath: session.worktreePath,
                    status: session.status,
                    createdAt: parseDate(session.createdAt) ?? Date(),
                    lastAccessedAt: parseDate(session.lastHeartbeatAt ?? session.updatedAt) ?? Date(),
                    updatedAt: parseDate(session.updatedAt) ?? Date()
                )

                try await databaseService.sessions.upsert(record)
            }

            logger.info("Synced \(supabaseSessions.count) sessions to SQLite")
        } catch {
            logger.warning("Failed to sync sessions: \(error)")
        }
    }

    // MARK: - Helpers

    /// Parse ISO8601 date string
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}
