import Foundation
import Logging

private let presenceStreamLogger = Logger(label: "app.presence.stream")

final class DOPresenceStreamClient {
    private var task: Task<Void, Never>?

    func start(
        userId: String,
        deviceId: String,
        streamURL: URL,
        authService: AuthService = .shared,
        onPayload: @escaping (DaemonPresencePayload) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        stop()

        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedDeviceId.isEmpty {
            presenceStreamLogger.warning("presence.do.device_id_missing")
        }

        task = Task {
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                do {
                    presenceStreamLogger.info("presence.do.connect_start")
                    let accessToken: String
                    do {
                        accessToken = try await authService.getAccessToken()
                    } catch {
                        presenceStreamLogger.warning("presence.do.auth_failed: \(error.localizedDescription)")
                        throw error
                    }

                    var request = URLRequest(url: streamURL)
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw PresenceTokenServiceError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw PresenceTokenServiceError.requestFailed("HTTP \(httpResponse.statusCode)")
                    }

                    presenceStreamLogger.info("presence.do.connect_ok")
                    attempt = 0

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }

                        let payloadLine: String
                        if trimmed.hasPrefix("data:") {
                            payloadLine = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            payloadLine = trimmed
                        }

                        guard let data = payloadLine.data(using: .utf8) else { continue }
                        guard let payload = try? JSONDecoder().decode(DaemonPresencePayload.self, from: data) else {
                            presenceStreamLogger.warning("presence.do.payload_ignored")
                            continue
                        }

                        if payload.userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != normalizedUserId {
                            presenceStreamLogger.warning("presence.do.payload_ignored")
                            continue
                        }
                        if payload.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().isEmpty {
                            presenceStreamLogger.warning("presence.do.payload_ignored")
                            continue
                        }

                        presenceStreamLogger.debug("presence.do.payload_applied")
                        onPayload(payload)
                    }
                } catch {
                    presenceStreamLogger.warning("presence.do.connect_failed: \(error.localizedDescription)")
                    onError(error)
                }

                if Task.isCancelled { break }

                let backoff = min(5.0, pow(2.0, Double(min(attempt, 5))) * 0.5)
                presenceStreamLogger.info("presence.do.reconnect_attempt", metadata: ["delay_s": "\(backoff)"])
                try? await Task.sleep(for: .seconds(backoff))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
