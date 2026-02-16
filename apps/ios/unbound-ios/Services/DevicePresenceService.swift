//
//  DevicePresenceService.swift
//  unbound-ios
//
//  Manages device presence/heartbeat by periodically updating last_seen_at in Supabase.
//  Also subscribes to other devices (macOS) via Supabase Realtime to track their online status.
//

import CryptoKit
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
    private(set) var daemonStatusVersion: Int = 0

    // MARK: - Private Properties

    private var supabase: SupabaseClient?
    private var deviceId: String?
    private var userId: String?
    private var normalizedDaemonPresenceUserID: String?
    private var heartbeatTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var statusCheckTimer: Timer?
    private var networkMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.unbound.presence.network")
    private var daemonLastHeartbeatAt: [String: Date] = [:]
    private var daemonExplicitOfflineAt: [String: Date] = [:]
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
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCurrentDeviceId = self.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCurrentUserId = self.userId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Avoid tearing down/recreating subscriptions when auth/session callbacks
        // call start repeatedly for the same device/user.
        if normalizedCurrentDeviceId == normalizedDeviceId,
           normalizedCurrentUserId == normalizedUserId,
           heartbeatTask != nil {
            logger.debug("DevicePresenceService start ignored (already running)")
            return
        }

        if self.deviceId != nil || self.userId != nil || self.supabase != nil {
            stop()
        }

        self.supabase = supabase
        self.deviceId = normalizedDeviceId
        self.userId = normalizedUserId
        normalizedDaemonPresenceUserID = normalizedUserId

        startNetworkMonitoring()
        startHeartbeat()
        startStatusCheckTimer()

        // Send immediate heartbeat on start
        Task {
            await sendHeartbeat()
            await fetchAndSubscribeToDevices()
            await startDaemonPresenceSubscription()
        }

        logger.info("DevicePresenceService started for device: \(normalizedDeviceId)")
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
        normalizedDaemonPresenceUserID = nil
        monitoredDevices = []
        daemonLastHeartbeatAt = [:]
        daemonExplicitOfflineAt = [:]
        daemonStatusVersion = 0

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

    /// Returns true when the presence service is already active for the given device/user pair.
    func isRunning(deviceId: String, userId: String) -> Bool {
        guard heartbeatTask != nil else { return false }
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return self.deviceId == normalizedDeviceId && self.userId == normalizedUserId
    }

    /// Check if a device daemon is available for remote commands.
    /// Availability allows `unknown` bootstrap state and only blocks explicit/derived offline.
    func isDeviceDaemonAvailable(id: String) -> Bool {
        daemonAvailability(id: id) != .offline
    }

    /// Resolve daemon availability state from heartbeat stream.
    func daemonAvailability(id: String) -> DeviceDaemonAvailability {
        let normalizedID = Self.normalizeDaemonPresenceIdentifier(id)
        if let lastHeartbeat = daemonLastHeartbeatAt[normalizedID] {
            if Date().timeIntervalSince(lastHeartbeat) <= daemonHeartbeatTTL {
                return .online
            }
            return .offline
        }
        if daemonExplicitOfflineAt[normalizedID] != nil {
            return .offline
        }
        return .unknown
    }

    /// Resolve the most recent status signal between Supabase `last_seen_at` and daemon presence events.
    /// This is intended for UI display to avoid stale offline indicators when one signal lags behind.
    func mergedDeviceStatus(id: String, supabaseLastSeenAt: Date?, supabaseThreshold: TimeInterval = 15.0) -> SyncedDevice.DeviceStatus {
        let normalizedID = Self.normalizeDaemonPresenceIdentifier(id)
        let freshnessThreshold = max(supabaseThreshold, daemonHeartbeatTTL)

        var signals: [(status: SyncedDevice.DeviceStatus, timestamp: Date)] = []
        if let supabaseLastSeenAt {
            signals.append((status: .online, timestamp: supabaseLastSeenAt))
        }
        if let daemonOnlineAt = daemonLastHeartbeatAt[normalizedID] {
            signals.append((status: .online, timestamp: daemonOnlineAt))
        }
        if let daemonOfflineAt = daemonExplicitOfflineAt[normalizedID] {
            signals.append((status: .offline, timestamp: daemonOfflineAt))
        }

        guard let latestSignal = signals.max(by: { $0.timestamp < $1.timestamp }) else {
            return .offline
        }

        switch latestSignal.status {
        case .online:
            return Date().timeIntervalSince(latestSignal.timestamp) <= freshnessThreshold ? .online : .offline
        case .offline, .busy:
            return .offline
        }
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

    // MARK: - Daemon Presence via Ably (legacy)

    private struct DaemonPresencePayload: Decodable {
        let schemaVersion: Int
        let userID: String
        let deviceID: String
        let status: String
        let source: String?
        let sentAtMS: Int64
        let seq: Int?
        let ttlMS: Int?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case userID = "user_id"
            case deviceID = "device_id"
            case status
            case source
            case sentAtMS = "sent_at_ms"
            case seq
            case ttlMS = "ttl_ms"
        }
    }

    private func startDaemonPresenceSubscription() async {
        #if canImport(Ably)
        guard let normalizedUserID = normalizedDaemonPresenceUserID else { return }

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
        let channelName = Config.daemonPresenceChannel(userId: normalizedUserID)
        logger.info(
            "Starting daemon presence subscription",
            metadata: daemonPresenceLogMetadata(
                eventCode: "ios.presence.daemon.subscribe_start",
                channel: channelName,
                status: "subscribe_start"
            )
        )

        let channel = realtime.channels.get(channelName)
        let listener = channel.subscribe(Config.daemonPresenceEventName) { [weak self] message in
            guard let self else { return }
            guard let payload = Self.decodeDaemonPresencePayload(message.data) else {
                logger.warning(
                    "Failed to decode daemon presence payload",
                    metadata: self.daemonPresenceLogMetadata(
                        eventCode: "ios.presence.daemon.decode_failed",
                        channel: channelName,
                        status: "decode_failed"
                    )
                )
                return
            }
            Task { @MainActor [weak self] in
                self?.consumeDaemonPresencePayload(payload, channelName: channelName)
            }
        }

        channel.attach { [weak self] error in
            guard let self, let error else { return }
            logger.warning(
                "Failed to attach daemon presence channel: \(error.localizedDescription)",
                metadata: self.daemonPresenceLogMetadata(
                    eventCode: "ios.presence.daemon.attach_failed",
                    channel: channelName,
                    status: "attach_failed"
                )
            )
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

    private func consumeDaemonPresencePayload(_ payload: DaemonPresencePayload, channelName: String) {
        guard let normalizedExpectedUserID = normalizedDaemonPresenceUserID else { return }
        if !Self.daemonPresenceUserIDsMatch(
            expected: normalizedExpectedUserID,
            payload: payload.userID
        ) {
            logger.warning(
                "Ignoring daemon presence payload for unexpected user payload_user_id=\(payload.userID) payload_device_id=\(payload.deviceID)",
                metadata: daemonPresenceLogMetadata(
                    eventCode: "ios.presence.daemon.payload_user_mismatch",
                    channel: channelName,
                    status: payload.status,
                    payloadUserID: payload.userID,
                    payloadDeviceID: payload.deviceID
                )
            )
            return
        }

        let normalizedDeviceID = Self.normalizeDaemonPresenceIdentifier(payload.deviceID)
        guard !normalizedDeviceID.isEmpty else {
            logger.warning(
                "Ignoring daemon presence payload with empty device id payload_user_id=\(payload.userID)",
                metadata: daemonPresenceLogMetadata(
                    eventCode: "ios.presence.daemon.payload_device_empty",
                    channel: channelName,
                    status: payload.status,
                    payloadUserID: payload.userID,
                    payloadDeviceID: payload.deviceID
                )
            )
            return
        }

        let receivedAt = Date()
        let payloadSentAt = Date(timeIntervalSince1970: TimeInterval(payload.sentAtMS) / 1000)
        let payloadAgeSeconds = receivedAt.timeIntervalSince(payloadSentAt)
        let knownSyncedDevice = SyncedDataService.shared.devices.contains {
            $0.id.uuidString.lowercased() == normalizedDeviceID
        }

        switch payload.status {
        case "online":
            // Use local receipt time for liveness checks so clock skew does not mark online daemons as offline.
            daemonLastHeartbeatAt[normalizedDeviceID] = receivedAt
            daemonExplicitOfflineAt.removeValue(forKey: normalizedDeviceID)
            daemonStatusVersion &+= 1
            logger.debug(
                "Applied daemon presence heartbeat status=\(payload.status) device_id=\(normalizedDeviceID) known_device=\(knownSyncedDevice) payload_age_s=\(String(format: "%.3f", payloadAgeSeconds))",
                metadata: daemonPresenceLogMetadata(
                    eventCode: "ios.presence.daemon.payload_applied",
                    channel: channelName,
                    status: payload.status,
                    payloadUserID: payload.userID,
                    payloadDeviceID: normalizedDeviceID,
                    payloadAgeSeconds: payloadAgeSeconds,
                    matchedSyncedDevice: knownSyncedDevice
                )
            )
        case "offline":
            daemonLastHeartbeatAt.removeValue(forKey: normalizedDeviceID)
            daemonExplicitOfflineAt[normalizedDeviceID] = receivedAt
            daemonStatusVersion &+= 1
            logger.debug(
                "Applied daemon presence heartbeat status=\(payload.status) device_id=\(normalizedDeviceID) known_device=\(knownSyncedDevice) payload_age_s=\(String(format: "%.3f", payloadAgeSeconds))",
                metadata: daemonPresenceLogMetadata(
                    eventCode: "ios.presence.daemon.payload_applied",
                    channel: channelName,
                    status: payload.status,
                    payloadUserID: payload.userID,
                    payloadDeviceID: normalizedDeviceID,
                    payloadAgeSeconds: payloadAgeSeconds,
                    matchedSyncedDevice: knownSyncedDevice
                )
            )
        default:
            // Ignore unknown statuses to preserve forward compatibility.
            logger.debug(
                "Ignored daemon presence heartbeat with unknown status=\(payload.status) device_id=\(normalizedDeviceID) known_device=\(knownSyncedDevice) payload_age_s=\(String(format: "%.3f", payloadAgeSeconds))",
                metadata: daemonPresenceLogMetadata(
                    eventCode: "ios.presence.daemon.payload_ignored",
                    channel: channelName,
                    status: payload.status,
                    payloadUserID: payload.userID,
                    payloadDeviceID: normalizedDeviceID,
                    payloadAgeSeconds: payloadAgeSeconds,
                    matchedSyncedDevice: knownSyncedDevice
                )
            )
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

    static func daemonPresenceUserIDsMatch(expected: String, payload: String) -> Bool {
        normalizeDaemonPresenceIdentifier(expected) == normalizeDaemonPresenceIdentifier(payload)
    }

    private func daemonPresenceLogMetadata(
        eventCode: String,
        channel: String,
        status: String,
        payloadUserID: String? = nil,
        payloadDeviceID: String? = nil,
        payloadAgeSeconds: TimeInterval? = nil,
        matchedSyncedDevice: Bool? = nil
    ) -> Logger.Metadata {
        var metadata: Logger.Metadata = [
            "event_code": .string(eventCode),
            "component": .string("presence.daemon"),
            "channel": .string(channel),
            "event": .string(Config.daemonPresenceEventName),
            "expected_user_id_hash": .string(Self.observabilityHash(normalizedDaemonPresenceUserID)),
            "payload_user_id_hash": .string(Self.observabilityHash(payloadUserID)),
            "payload_device_id_hash": .string(Self.observabilityHash(payloadDeviceID)),
            "device_id_hash": .string(Self.observabilityHash(deviceId)),
            "status": .string(status),
        ]

        if let payloadAgeSeconds {
            metadata["payload_age_seconds"] = .string(String(format: "%.3f", payloadAgeSeconds))
        }

        if let matchedSyncedDevice {
            metadata["payload_device_known"] = .string(matchedSyncedDevice ? "true" : "false")
        }

        return metadata
    }

    private static func normalizeDaemonPresenceIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func observabilityHash(_ value: String?) -> String {
        guard let value else { return "unknown" }
        let normalized = normalizeDaemonPresenceIdentifier(value)
        guard !normalized.isEmpty else { return "unknown" }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
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

#if DEBUG
extension DevicePresenceService {
    func _testResetDaemonPresenceState() {
        daemonLastHeartbeatAt = [:]
        daemonExplicitOfflineAt = [:]
        daemonStatusVersion = 0
    }

    func _testApplyDaemonPresence(deviceID: String, status: String, at timestamp: Date) {
        let normalizedDeviceID = Self.normalizeDaemonPresenceIdentifier(deviceID)
        guard !normalizedDeviceID.isEmpty else { return }

        switch status {
        case "online":
            daemonLastHeartbeatAt[normalizedDeviceID] = timestamp
            daemonExplicitOfflineAt.removeValue(forKey: normalizedDeviceID)
            daemonStatusVersion &+= 1
        case "offline":
            daemonLastHeartbeatAt.removeValue(forKey: normalizedDeviceID)
            daemonExplicitOfflineAt[normalizedDeviceID] = timestamp
            daemonStatusVersion &+= 1
        default:
            break
        }
    }
}
#endif
