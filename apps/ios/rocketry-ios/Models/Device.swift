import Foundation

struct Device: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: DeviceType
    let hostname: String
    let ipAddress: String
    let status: DeviceStatus
    let lastSeen: Date
    let osVersion: String
    let projectCount: Int

    enum DeviceType: String, CaseIterable, Codable {
        case macbookPro = "MacBook Pro"
        case macbookAir = "MacBook Air"
        case macMini = "Mac Mini"
        case macStudio = "Mac Studio"
        case macPro = "Mac Pro"
        case imac = "iMac"
        case linux = "Linux"
        case windows = "Windows"

        var iconName: String {
            switch self {
            case .macbookPro, .macbookAir:
                return "laptopcomputer"
            case .macMini, .macStudio:
                return "macmini"
            case .macPro:
                return "macpro.gen3"
            case .imac:
                return "desktopcomputer"
            case .linux, .windows:
                return "pc"
            }
        }
    }

    enum DeviceStatus: String, Codable {
        case online
        case offline
        case busy

        var displayName: String {
            rawValue.capitalized
        }
    }
}
