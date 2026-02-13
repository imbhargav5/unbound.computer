import Foundation

enum BillingUsageServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case missingDeviceId
    case invalidRequestURL
    case unauthorized
    case forbidden
    case deviceNotFound
    case server(statusCode: Int, message: String)
    case invalidResponse
    case decoding

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to view billing usage."
        case .missingDeviceId:
            return "Device identity is not available yet."
        case .invalidRequestURL:
            return "Billing service URL is invalid."
        case .unauthorized:
            return "Your session expired. Sign in again to load billing usage."
        case .forbidden:
            return "This device is not authorized to read billing usage."
        case .deviceNotFound:
            return "Device not found for this account."
        case .server(let statusCode, let message):
            if message.isEmpty {
                return "Billing usage request failed (\(statusCode))."
            }
            return "Billing usage request failed (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Billing service returned an invalid response."
        case .decoding:
            return "Billing usage data could not be parsed."
        }
    }
}

struct BillingUsageStatus: Decodable, Equatable {
    enum Plan: String, Decodable, Equatable {
        case free
        case paid
    }

    enum EnforcementState: String, Decodable, Equatable {
        case ok
        case nearLimit = "near_limit"
        case overQuota = "over_quota"
    }

    let plan: Plan
    let gateway: String
    let periodStart: String
    let periodEnd: String
    let commandsLimit: Int
    let commandsUsed: Int
    let commandsRemaining: Int
    let enforcementState: EnforcementState
    let updatedAt: String
}

enum BillingUsageCardState: Equatable {
    case loading
    case active(BillingUsageStatus)
    case nearLimit(BillingUsageStatus)
    case overLimit(BillingUsageStatus)
    case error(String)

    static func from(status: BillingUsageStatus) -> BillingUsageCardState {
        switch status.enforcementState {
        case .ok:
            return .active(status)
        case .nearLimit:
            return .nearLimit(status)
        case .overQuota:
            return .overLimit(status)
        }
    }
}

enum BillingUsageService {
    static func fetchUsageStatus(authService: AuthService) async throws -> BillingUsageStatus {
        guard authService.authState.isAuthenticated else {
            throw BillingUsageServiceError.notAuthenticated
        }

        guard let deviceId = DeviceTrustService.shared.deviceId?.uuidString else {
            throw BillingUsageServiceError.missingDeviceId
        }

        let accessToken = try await authService.getAccessToken()
        guard var components = URLComponents(
            url: Config.apiURL.appendingPathComponent("api/v1/mobile/billing/usage-status"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BillingUsageServiceError.invalidRequestURL
        }
        components.queryItems = [URLQueryItem(name: "deviceId", value: deviceId.lowercased())]
        guard let url = components.url else {
            throw BillingUsageServiceError.invalidRequestURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BillingUsageServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(BillingUsageStatus.self, from: data)
            } catch {
                throw BillingUsageServiceError.decoding
            }
        case 401:
            throw BillingUsageServiceError.unauthorized
        case 403:
            throw BillingUsageServiceError.forbidden
        case 404:
            throw BillingUsageServiceError.deviceNotFound
        default:
            throw BillingUsageServiceError.server(
                statusCode: httpResponse.statusCode,
                message: extractErrorMessage(from: data)
            )
        }
    }

    private static func extractErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String
        {
            return error
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
