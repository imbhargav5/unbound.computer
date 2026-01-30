import Foundation

// MARK: - Outbound Commands

enum RelayCommand: Codable, Sendable {
    case authenticate(token: String, deviceId: String)
    case subscribe(sessionId: String)
    case unsubscribe(sessionId: String)
    case joinSession(sessionId: String, role: DeviceRole, permission: Permission?)
    case leaveSession(sessionId: String)

    enum CodingKeys: String, CodingKey {
        case type
        case token
        case deviceId
        case sessionId
        case role
        case permission
    }

    enum CommandType: String, Codable {
        case authenticate = "AUTHENTICATE"
        case subscribe = "SUBSCRIBE"
        case unsubscribe = "UNSUBSCRIBE"
        case joinSession = "JOIN_SESSION"
        case leaveSession = "LEAVE_SESSION"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .authenticate(let token, let deviceId):
            try container.encode(CommandType.authenticate, forKey: .type)
            try container.encode(token, forKey: .token)
            try container.encode(deviceId, forKey: .deviceId)

        case .subscribe(let sessionId):
            try container.encode(CommandType.subscribe, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)

        case .unsubscribe(let sessionId):
            try container.encode(CommandType.unsubscribe, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)

        case .joinSession(let sessionId, let role, let permission):
            try container.encode(CommandType.joinSession, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(permission, forKey: .permission)

        case .leaveSession(let sessionId):
            try container.encode(CommandType.leaveSession, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)

        switch type {
        case .authenticate:
            let token = try container.decode(String.self, forKey: .token)
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            self = .authenticate(token: token, deviceId: deviceId)

        case .subscribe:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .subscribe(sessionId: sessionId)

        case .unsubscribe:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .unsubscribe(sessionId: sessionId)

        case .joinSession:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let role = try container.decode(DeviceRole.self, forKey: .role)
            let permission = try container.decodeIfPresent(Permission.self, forKey: .permission)
            self = .joinSession(sessionId: sessionId, role: role, permission: permission)

        case .leaveSession:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .leaveSession(sessionId: sessionId)
        }
    }
}

// MARK: - Inbound Events

enum RelayEvent: Codable, Sendable {
    case authSuccess(deviceId: String, accountId: String)
    case authFailure(reason: String)
    case subscribed(sessionId: String)
    case conversationEvent(ConversationEvent)
    case sessionJoined(sessionId: String)
    case error(code: String, message: String)

    enum CodingKeys: String, CodingKey {
        case type
        case deviceId
        case accountId
        case reason
        case sessionId
        case event
        case code
        case message
    }

    enum EventType: String, Codable {
        case authSuccess = "AUTH_SUCCESS"
        case authFailure = "AUTH_FAILURE"
        case subscribed = "SUBSCRIBED"
        case conversationEvent = "CONVERSATION_EVENT"
        case sessionJoined = "SESSION_JOINED"
        case error = "ERROR"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .authSuccess(let deviceId, let accountId):
            try container.encode(EventType.authSuccess, forKey: .type)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(accountId, forKey: .accountId)

        case .authFailure(let reason):
            try container.encode(EventType.authFailure, forKey: .type)
            try container.encode(reason, forKey: .reason)

        case .subscribed(let sessionId):
            try container.encode(EventType.subscribed, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)

        case .conversationEvent(let event):
            try container.encode(EventType.conversationEvent, forKey: .type)
            try container.encode(event, forKey: .event)

        case .sessionJoined(let sessionId):
            try container.encode(EventType.sessionJoined, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)

        case .error(let code, let message):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)

        switch type {
        case .authSuccess:
            let deviceId = try container.decode(String.self, forKey: .deviceId)
            let accountId = try container.decode(String.self, forKey: .accountId)
            self = .authSuccess(deviceId: deviceId, accountId: accountId)

        case .authFailure:
            let reason = try container.decode(String.self, forKey: .reason)
            self = .authFailure(reason: reason)

        case .subscribed:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .subscribed(sessionId: sessionId)

        case .conversationEvent:
            let event = try container.decode(ConversationEvent.self, forKey: .event)
            self = .conversationEvent(event)

        case .sessionJoined:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .sessionJoined(sessionId: sessionId)

        case .error:
            let code = try container.decode(String.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .error(code: code, message: message)
        }
    }
}

// MARK: - Supporting Types

enum DeviceRole: String, Codable, Sendable {
    case executor
    case controller
    case viewer
}

enum Permission: String, Codable, Sendable {
    case viewOnly = "view_only"
    case interact
    case fullControl = "full_control"
}
