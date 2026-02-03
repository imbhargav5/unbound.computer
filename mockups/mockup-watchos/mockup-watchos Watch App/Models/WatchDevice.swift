//
//  WatchDevice.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct WatchDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let type: WatchDeviceType
    let status: WatchDeviceStatus
    let activeSessionCount: Int
}

enum WatchDeviceType: String, CaseIterable {
    case macbookPro = "MacBook Pro"
    case macbookAir = "MacBook Air"
    case macMini = "Mac Mini"
    case macStudio = "Mac Studio"
    case macPro = "Mac Pro"
    case imac = "iMac"
    case linux = "Linux"

    var icon: String {
        switch self {
        case .macbookPro, .macbookAir:
            return "laptopcomputer"
        case .macMini, .macStudio:
            return "macmini"
        case .macPro:
            return "macpro.gen3"
        case .imac:
            return "desktopcomputer"
        case .linux:
            return "pc"
        }
    }

    var shortName: String {
        switch self {
        case .macbookPro: return "MBP"
        case .macbookAir: return "MBA"
        case .macMini: return "Mini"
        case .macStudio: return "Studio"
        case .macPro: return "Pro"
        case .imac: return "iMac"
        case .linux: return "Linux"
        }
    }
}

enum WatchDeviceStatus: String {
    case online
    case offline
    case busy

    var color: Color {
        switch self {
        case .online: return .green
        case .offline: return .gray
        case .busy: return .orange
        }
    }

    var icon: String {
        switch self {
        case .online: return "circle.fill"
        case .offline: return "circle"
        case .busy: return "circle.fill"
        }
    }
}
