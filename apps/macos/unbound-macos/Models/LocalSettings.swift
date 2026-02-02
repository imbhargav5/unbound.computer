//
//  LocalSettings.swift
//  unbound-macos
//
//  Local settings stored on device (UserDefaults)
//  Manages font size preferences and other UI settings
//

import SwiftUI

// MARK: - Font Size Preset

enum FontSizePreset: String, CaseIterable, Identifiable {
    case small = "Small"
    case large = "Large"

    var id: String { rawValue }

    /// Scale factor applied to base font sizes
    var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.9
        case .large: return 1.0
        }
    }

    var description: String {
        switch self {
        case .small: return "Compact interface"
        case .large: return "Default size"
        }
    }

    var iconName: String {
        switch self {
        case .small: return "textformat.size.smaller"
        case .large: return "textformat.size.larger"
        }
    }
}

// MARK: - Local Settings

@MainActor
@Observable
class LocalSettings {
    // MARK: - Singleton

    static let shared = LocalSettings()

    // MARK: - Keys

    private enum Keys {
        static let fontSizePreset = "fontSizePreset"
    }

    // MARK: - Properties

    var fontSizePreset: FontSizePreset {
        didSet {
            UserDefaults.standard.set(fontSizePreset.rawValue, forKey: Keys.fontSizePreset)
        }
    }

    // MARK: - Initialization

    private init() {
        // Load font size preset from UserDefaults
        if let savedPreset = UserDefaults.standard.string(forKey: Keys.fontSizePreset),
           let preset = FontSizePreset(rawValue: savedPreset) {
            self.fontSizePreset = preset
        } else {
            // Default to small (compact) preset
            self.fontSizePreset = .small
        }
    }

    // MARK: - Scaled Font Size

    /// Returns a font size scaled according to the current preset
    func scaled(_ size: CGFloat) -> CGFloat {
        size * fontSizePreset.scaleFactor
    }
}
