//
//  DevicePresenceService.swift
//  unbound-ios
//
//  Manages device presence/heartbeat by periodically updating last_seen_at in Supabase.
//  Also subscribes to other devices (macOS) via Supabase Realtime to track their online status.
//

import Foundation
import Logging
import Network
import Supabase
import Realtime

#if canImport(Ably)
import Ably
#endif

private let logger = Logger(label: "app.device")

enum DeviceDaemonAvailability: Equatable {
    case online
    case offline
    case unknown
}

/// Represents a monitored device with its online status
struct MonitoredDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let deviceType: String
    var lastSeenAt: Date
    var isOnline: Bool

    /// Check if the device is considered online (last seen within threshold)
    static func checkOnline(lastSeenAt: Date, threshold: TimeInterval = 12.0) -> Bool {
        Date().timeIntervalSince(lastSeenAt) <= threshold
    }
}

/// Service for managing device presence and heartbeat
@Observable
@MainActor
final class DevicePresenceService {
    static let shared = DevicePresenceService()

    // MARK: - Configuration

    private let heartbeatInterval: TimeInterval = 5.0
    private let offlineThreshold: TimeInterval = 12.0

    // MARK: - State

    private(set) var isNetworkAvailable: Bool = false
    private(set) var isHeartbeatRunning: Bool = false
    private(set) var monitoredDevices: [MonitoredDevice] = []

    // MARK: - Private Properties

    private var supabase: SupabaseClient?
    private var deviceId: String?
    private var userId: String?
    private var heartbeatTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var statusCheckTimer: Timer?
    private var networkMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.unbound.presence.network")
    private var daemonLastHeartbeatAt: [String: Date] = [:]
    private var daemonExplicitOfflineDevices: Set<String> = []
    private let daemonHeartbeatTTL: TimeInterval = 12.0

    #if canImport(Ably)
    private var daemonPresenceRealtime: ARTRealtime?
    private var daemonPresenceChannel: ARTRealtimeChannel?
    private var daemonPresenceListener: ARTEventListener?
    #endif

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start the presence service
    /// - Parameters:
    ///   - supabase: The Supabase client to use
    ///   - deviceId: This device's ID
    ///   - userId: The current user's ID
    func start(supabase: SupabaseClient, deviceId: String, userId: String) {
        self.supabase = supabase
        self.deviceId = deviceId
        self.userId = userId

        startNetworkMonitoring()
        startHeartbeat()
        startStatusCheckTimer()

        // Send immediate heartbeat on start
        Task {
            await sendHeartbeat()
            await fetchAndSubscribeToDevices()
            await startDaemonPresenceSubscription()
        }

        logger.info("DevicePresenceService started for device: \(deviceId)")
    }

    /// Stop the presence service
    func stop() {
        stopHeartbeat()
        stopNetworkMonitoring()
        stopStatusCheckTimer()
        unsubscribeFromDevices()
        stopDaemonPresenceSubscription()

        supabase = nil
        deviceId = nil
        userId = nil
        monitoredDevices = []
        daemonLastHeartbeatAt = [:]
        daemonExplicitOfflineDevices = []

        logger.info("DevicePresenceService stopped")
    }

    /// Send an immediate heartbeat (e.g., when app becomes active)
    func sendImmediateHeartbeat() async {
        await sendHeartbeat()
    }

    /// Get a specific monitored device by ID
    func getDevice(id: String) -> MonitoredDevice? {
        monitoredDevices.first { $0.id == id }
    }

    /// Check if a specific device is online
    func isDeviceOnline(id: String) -> Bool {
        guard let device = getDevice(id: id) else { return false }
        return device.isOnline
    }

    /// Check if a device daemon is available for remote commands.
    /// Availability allows `unknown` bootstrap state and only blocks explicit/derived offline.
    func isDeviceDaemonAvailable(id: String) -> Bool {
        daemonAvailability(id: id) != .offline
    }

    /// Resolve daemon availability state from heartbeat stream.
    func daemonAvailability(id: String) -> DeviceDaemonAvailability {
        let normalizedID = id.lowercased()
        if let lastHeartbeat = daemonLastHeartbeatAt[normalizedID] {
            if Date().timeIntervalSince(lastHeartbeat) <= daemonHeartbeatTTL {
                return .online
            }
            return .offline
        }
        if daemonExplicitOfflineDevices.contains(normalizedID) {
            return .offline
        }
        return .unknown
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }

        isHeartbeatRunning = true
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                if self.isNetworkAvailable {
                    await self.sendHeartbeat()
                }

                try? await Task.sleep(for: .seconds(self.heartbeatInterval))
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        isHeartbeatRunning = false
    }

    private func sendHeartbeat() async {
        guard let supabase, let deviceId else { return }

        do {
            let now = ISO8601DateFormatter().string(from: Date())

            try await supabase
                .from("devices")
                .update(["last_seen_at": now])
                .eq("id", value: deviceId)
                .execute()
        } catch {
            logger.error("Failed to send heartbeat: \(error)")
        }
    }

    // MARK: - Device Monitoring via Realtime

    private func fetchAndSubscribeToDevices() async {
        guard let supabase, let userId, let deviceId else { return }

        // First, fetch existing mac devices
        do {
            let response: [DeviceRecord] = try await supabase
                .from("devices")
                .select()
                .eq("user_id", value: userId)
                .eq("device_type", value: "mac-desktop")
                .neq("id", value: deviceId)
                .execute()
                .value

            monitoredDevices = response.map { record in
                MonitoredDevice(
                    id: record.id,
                    name: record.name,
                    deviceType: record.deviceType,
                    lastSeenAt: record.lastSeenAt ?? Date.distantPast,
                    isOnline: MonitoredDevice.checkOnline(
                        lastSeenAt: record.lastSeenAt ?? Date.distantPast,
                        threshold: offlineThreshold
                    )
                )
            }

            logger.info("Fetched \(monitoredDevices.count) mac devices to monitor")
        } catch {
            logger.error("Failed to fetch devices: \(error)")
        }

        // Subscribe to realtime changes
        await subscribeToDeviceChanges()
    }

    private func subscribeToDeviceChanges() async {
        guard let supabase, let userId else { return }

        // Unsubscribe from existing channel if any
        unsubscribeFromDevices()

        let channel = supabase.realtimeV2.channel("device-presence-\(userId)")

        let changes = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "devices",
            filter: "user_id=eq.\(userId)"
        )

        await channel.subscribe()
        self.realtimeChannel = channel

        logger.info("Subscribed to device presence changes")

        // Listen for changes
        Task { [weak self] in
            for await change in changes {
                guard let self else { break }

                if let record = change.record as? [String: Any],
                   let id = record["id"] as? String,
                   let deviceType = record["device_type"] as? String,
                   deviceType == "mac-desktop",
                   id != self.deviceId {

                    let name = record["name"] as? String ?? "Unknown"
                    let lastSeenAtString = record["last_seen_at"] as? String

                    let lastSeenAt: Date
                    if let dateString = lastSeenAtString {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        lastSeenAt = formatter.date(from: dateString) ?? Date.distantPast
                    } else {
                        lastSeenAt = Date.distantPast
                    }

                    let isOnline = MonitoredDevice.checkOnline(
                        lastSeenAt: lastSeenAt,
                        threshold: self.offlineThreshold
                    )

                    if let index = self.monitoredDevices.firstIndex(where: { $0.id == id }) {
                        self.monitoredDevices[index].lastSeenAt = lastSeenAt
                        self.monitoredDevices[index].isOnline = isOnline
                    } else {
                        // New device
                        self.monitoredDevices.append(MonitoredDevice(
                            id: id,
                            name: name,
                            deviceType: deviceType,
                            lastSeenAt: lastSeenAt,
                            isOnline: isOnline
                        ))
                    }

                    logger.debug("Device \(name) updated: online=\(isOnline)")
                }
            }
        }
    }

    private func unsubscribeFromDevices() {
        if let channel = realtimeChannel {
            Task {
                await channel.unsubscribe()
            }
            realtimeChannel = nil
        }
    }

    // MARK: - Status Check Timer

    /// Periodically check device status to detect offline devices
    /// (in case we miss realtime updates or device stops sending heartbeats)
    private func startStatusCheckTimer() {
        stopStatusCheckTimer()

        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                for index in self.monitoredDevices.indices {
                    let wasOnline = self.monitoredDevices[index].isOnline
                    let isOnline = MonitoredDevice.checkOnline(
                        lastSeenAt: self.monitoredDevices[index].lastSeenAt,
                        threshold: self.offlineThreshold
                    )

                    if wasOnline != isOnline {
                        self.monitoredDevices[index].isOnline = isOnline
                        logger.debug("Device \(self.monitoredDevices[index].name) status changed: online=\(isOnline)")
                    }
                }
            }
        }
    }

    private func stopStatusCheckTimer() {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
    }

    // MARK: - Daemon Presence via Ably

    private struct DaemonPresencePayload: Decodable {
        let schemaVersion: Int
        let userID: String
        let deviceID: String
        let status: String
        let source: String?
        let sentAtMS: Int64

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case userID = "user_id"
            case deviceID = "device_id"
            case status
            case source
            case sentAtMS = "sent_at_ms"
        }
    }

    private func startDaemonPresenceSubscription() async {
        #if canImport(Ably)
        guard let userId else { return }

        stopDaemonPresenceSubscription()

        let tokenAuthURL = Config.ablyTokenAuthURL
        let options = ARTClientOptions()
        options.autoConnect = true
        options.authCallback = { _, callback in
            Task {
                do {
                    let details = try await AblyRemoteCommandTransport.fetchRealtimeTokenDetails(
                        tokenAuthURL: tokenAuthURL,
                        authService: .shared,
                        keychainService: .shared
                    )
                    callback(details, nil)
                } catch {
                    let nsError = await MainActor.run {
                        AblyRemoteCommandTransport.tokenAuthNSError(error)
                    }
                    callback(nil, nsError)
                }
            }
        }

        let realtime = ARTRealtime(options: options)
        let channelName = Config.daemonPresenceChannel(userId: userId)
        let channel = realtime.channels.get(channelName)
        let listener = channel.subscribe(Config.daemonPresenceEventName) { [weak self] message in
            guard let self else { return }
            guard let payload = Self.decodeDaemonPresencePayload(message.data) else { return }
            Task { @MainActor [weak self] in
                self?.consumeDaemonPresencePayload(payload)
            }
        }

        daemonPresenceRealtime = realtime
        daemonPresenceChannel = channel
        daemonPresenceListener = listener

        logger.info("Subscribed to daemon presence heartbeat stream on channel: \(channelName)")
        #endif
    }

    private func stopDaemonPresenceSubscription() {
        #if canImport(Ably)
        if let channel = daemonPresenceChannel, let listener = daemonPresenceListener {
            channel.unsubscribe(listener)
        }
        daemonPresenceListener = nil
        daemonPresenceChannel = nil

        daemonPresenceRealtime?.close()
        daemonPresenceRealtime = nil
        #endif
    }

    private func consumeDaemonPresencePayload(_ payload: DaemonPresencePayload) {
        guard let userId else { return }
        guard payload.userID == userId else { return }

        let normalizedDeviceID = payload.deviceID.lowercased()
        let heartbeatDate = Date(timeIntervalSince1970: TimeInterval(payload.sentAtMS) / 1000)

        switch payload.status {
        case "online":
            daemonLastHeartbeatAt[normalizedDeviceID] = heartbeatDate
            daemonExplicitOfflineDevices.remove(normalizedDeviceID)
        case "offline":
            daemonLastHeartbeatAt.removeValue(forKey: normalizedDeviceID)
            daemonExplicitOfflineDevices.insert(normalizedDeviceID)
        default:
            // Ignore unknown statuses to preserve forward compatibility.
            break
        }
    }

    private static func decodeDaemonPresencePayload(_ data: Any?) -> DaemonPresencePayload? {
        guard let data else { return nil }

        let decodedData: Data?
        if let typed = data as? Data {
            decodedData = typed
        } else if let typed = data as? String {
            decodedData = typed.data(using: .utf8)
        } else if JSONSerialization.isValidJSONObject(data) {
            decodedData = try? JSONSerialization.data(withJSONObject: data)
        } else {
            decodedData = nil
        }

        guard let decodedData else { return nil }
        return try? JSONDecoder().decode(DaemonPresencePayload.self, from: decodedData)
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        guard networkMonitor == nil else { return }

        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let nowAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = nowAvailable
                // Send immediate heartbeat when network becomes available.
                if !wasAvailable && nowAvailable {
                    logger.info("Network restored - sending immediate heartbeat")
                    await self.sendHeartbeat()
                }

                if !nowAvailable {
                    logger.warning("Network unavailable")
                }
            }
        }

        networkMonitor?.start(queue: monitorQueue)
    }

    private func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }
}

// MARK: - Device Record for Decoding

private struct DeviceRecord: Decodable {
    let id: String
    let name: String
    let deviceType: String
    let lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case deviceType = "device_type"
        case lastSeenAt = "last_seen_at"
    }
}
