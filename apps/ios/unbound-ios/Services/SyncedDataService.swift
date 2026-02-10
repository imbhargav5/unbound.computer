//
//  SyncedDataService.swift
//  unbound-ios
//
//  Service that provides access to synced repositories, sessions, and devices from Supabase.
//  UI components observe this service to display synced data.
//

import Foundation
import Logging

private let logger = Logger(label: "app.sync")

// MARK: - UI Models

/// Device model for UI display (synced from Supabase)
struct SyncedDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let deviceType: DeviceType
    let hostname: String?
    let isActive: Bool
    let lastSeenAt: Date?
    let createdAt: Date

    /// Device online status based on last_seen_at timestamp
    var status: DeviceStatus {
        guard let lastSeen = lastSeenAt else { return .offline }
        let threshold: TimeInterval = 15.0 // seconds
        return Date().timeIntervalSince(lastSeen) <= threshold ? .online : .offline
    }

    /// Map Supabase device_type to UI DeviceType
    enum DeviceType: String, CaseIterable, Codable {
        case macDesktop = "mac-desktop"
        case winDesktop = "win-desktop"
        case linuxDesktop = "linux-desktop"
        case iosTablet = "ios-tablet"
        case iosPhone = "ios-phone"
        case androidTablet = "android-tablet"
        case androidPhone = "android-phone"
        case webBrowser = "web-browser"

        var displayName: String {
            switch self {
            case .macDesktop: return "Mac"
            case .winDesktop: return "Windows"
            case .linuxDesktop: return "Linux"
            case .iosTablet: return "iPad"
            case .iosPhone: return "iPhone"
            case .androidTablet: return "Android Tablet"
            case .androidPhone: return "Android Phone"
            case .webBrowser: return "Web Browser"
            }
        }

        var iconName: String {
            switch self {
            case .macDesktop: return "desktopcomputer"
            case .winDesktop, .linuxDesktop: return "pc"
            case .iosTablet, .androidTablet: return "ipad"
            case .iosPhone, .androidPhone: return "iphone"
            case .webBrowser: return "globe"
            }
        }

        /// Check if this is an executor device type (can run Claude Code)
        var isExecutor: Bool {
            switch self {
            case .macDesktop, .winDesktop, .linuxDesktop:
                return true
            default:
                return false
            }
        }
    }

    enum DeviceStatus: String {
        case online
        case offline
        case busy

        var displayName: String {
            rawValue.capitalized
        }
    }
}

/// Repository model for UI display
struct SyncedRepository: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let defaultBranch: String?
    let remoteUrl: String?
    let lastAccessedAt: Date
    let createdAt: Date

    init(from record: RepositoryRecord) {
        self.id = UUID(uuidString: record.id) ?? UUID()
        self.name = record.name
        self.path = record.path
        self.defaultBranch = record.defaultBranch
        self.remoteUrl = record.defaultRemote
        self.lastAccessedAt = record.lastAccessedAt
        self.createdAt = record.createdAt
    }
}

/// Session model for UI display
struct SyncedSession: Identifiable, Hashable {
    let id: UUID
    let title: String
    let repositoryId: UUID?
    let deviceId: UUID?
    let worktreePath: String?
    let status: CodingSessionStatus
    let lastAccessedAt: Date
    let createdAt: Date

    /// Backward-compatible alias used by existing UI code.
    var name: String { title }

    init(from record: SessionRecord) {
        self.id = UUID(uuidString: record.id) ?? UUID()
        self.title = record.title
        self.repositoryId = UUID(uuidString: record.repositoryId)
        self.deviceId = record.deviceId.flatMap { UUID(uuidString: $0) }
        self.worktreePath = record.worktreePath
        self.status = CodingSessionStatus(rawValue: record.status) ?? .active
        self.lastAccessedAt = record.lastAccessedAt
        self.createdAt = record.createdAt
    }

    var isActive: Bool {
        status == .active
    }
}

// MARK: - Synced Data Service

/// Service that provides access to synced data from SQLite and Supabase
/// UI components should observe this service for repository, session, and device data
@Observable
final class SyncedDataService {
    static let shared = SyncedDataService()

    private let databaseService: DatabaseService

    // Published data for UI observation
    private(set) var devices: [SyncedDevice] = []
    private(set) var repositories: [SyncedRepository] = []
    private(set) var sessions: [SyncedSession] = []
    private(set) var isLoading = false
    private(set) var lastSyncError: Error?

    private init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }

    // MARK: - Device Updates

    /// Update devices from Supabase response
    func updateDevices(_ syncedDevices: [SyncedDevice]) {
        devices = syncedDevices
        logger.debug("Updated \(syncedDevices.count) devices")
    }

    /// Get executor devices only (Mac, Windows, Linux - devices that can run Claude Code)
    var executorDevices: [SyncedDevice] {
        devices.filter { $0.deviceType.isExecutor }
    }

    /// Get online devices
    var onlineDevices: [SyncedDevice] {
        devices.filter { $0.status == .online }
    }

    /// Get device by ID
    func device(id: UUID) -> SyncedDevice? {
        devices.first { $0.id == id }
    }

    // MARK: - Loading Data

    /// Load all data from SQLite
    func loadAll() async {
        isLoading = true
        lastSyncError = nil

        do {
            async let reposTask = loadRepositories()
            async let sessionsTask = loadSessions()

            let (repos, sess) = try await (reposTask, sessionsTask)
            repositories = repos
            sessions = sess

            logger.info("Loaded \(repos.count) repositories, \(sess.count) sessions")
        } catch {
            lastSyncError = error
            logger.error("Failed to load data: \(error)")
        }

        isLoading = false
    }

    /// Load repositories from SQLite
    private func loadRepositories() async throws -> [SyncedRepository] {
        let records = try await databaseService.repositories.fetchAll()
        return records.map { SyncedRepository(from: $0) }
    }

    /// Load sessions from SQLite
    private func loadSessions() async throws -> [SyncedSession] {
        let records = try await databaseService.sessions.fetchAll()
        return records.map { SyncedSession(from: $0) }
    }

    // MARK: - Filtered Access

    /// Get active sessions only
    var activeSessions: [SyncedSession] {
        sessions.filter { $0.isActive }
    }

    /// Get sessions for a specific repository
    func sessions(for repositoryId: UUID) -> [SyncedSession] {
        sessions.filter { $0.repositoryId == repositoryId }
    }

    /// Get repository by ID
    func repository(id: UUID) -> SyncedRepository? {
        repositories.first { $0.id == id }
    }

    /// Get session by ID
    func session(id: UUID) -> SyncedSession? {
        sessions.first { $0.id == id }
    }

    /// Get repository for a session
    func repository(for session: SyncedSession) -> SyncedRepository? {
        guard let repoId = session.repositoryId else { return nil }
        return repository(id: repoId)
    }

    /// Get device for a session
    func device(for session: SyncedSession) -> SyncedDevice? {
        guard let deviceId = session.deviceId else { return nil }
        return device(id: deviceId)
    }

    /// Recent sessions sorted by last accessed, limited to 10
    var recentSessions: [SyncedSession] {
        sessions
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Refresh

    /// Force refresh data from SQLite
    func refresh() async {
        await loadAll()
    }
}
