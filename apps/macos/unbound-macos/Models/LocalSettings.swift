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
        static let leftSidebarVisible = "leftSidebarVisible"
        static let rightSidebarVisible = "rightSidebarVisible"
        static let isZenModeEnabled = "isZenModeEnabled"
        static let lastLeftSidebarVisible = "lastLeftSidebarVisible"
        static let lastRightSidebarVisible = "lastRightSidebarVisible"
    }

    // MARK: - Properties

    var fontSizePreset: FontSizePreset {
        didSet {
            UserDefaults.standard.set(fontSizePreset.rawValue, forKey: Keys.fontSizePreset)
        }
    }

    var leftSidebarVisible: Bool {
        didSet {
            UserDefaults.standard.set(leftSidebarVisible, forKey: Keys.leftSidebarVisible)
        }
    }

    var rightSidebarVisible: Bool {
        didSet {
            UserDefaults.standard.set(rightSidebarVisible, forKey: Keys.rightSidebarVisible)
        }
    }

    var isZenModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isZenModeEnabled, forKey: Keys.isZenModeEnabled)
        }
    }

    private var lastLeftSidebarVisible: Bool {
        didSet {
            UserDefaults.standard.set(lastLeftSidebarVisible, forKey: Keys.lastLeftSidebarVisible)
        }
    }

    private var lastRightSidebarVisible: Bool {
        didSet {
            UserDefaults.standard.set(lastRightSidebarVisible, forKey: Keys.lastRightSidebarVisible)
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

        let storedLeftSidebarVisible = UserDefaults.standard.object(forKey: Keys.leftSidebarVisible) as? Bool ?? true
        let storedRightSidebarVisible = UserDefaults.standard.object(forKey: Keys.rightSidebarVisible) as? Bool ?? true
        let storedZenModeEnabled = UserDefaults.standard.object(forKey: Keys.isZenModeEnabled) as? Bool ?? false
        let storedLastLeftSidebarVisible = UserDefaults.standard.object(forKey: Keys.lastLeftSidebarVisible) as? Bool ?? storedLeftSidebarVisible
        let storedLastRightSidebarVisible = UserDefaults.standard.object(forKey: Keys.lastRightSidebarVisible) as? Bool ?? storedRightSidebarVisible

        self.leftSidebarVisible = storedLeftSidebarVisible
        self.rightSidebarVisible = storedRightSidebarVisible
        self.isZenModeEnabled = storedZenModeEnabled
        self.lastLeftSidebarVisible = storedLastLeftSidebarVisible
        self.lastRightSidebarVisible = storedLastRightSidebarVisible

        if isZenModeEnabled {
            leftSidebarVisible = false
            rightSidebarVisible = false
        }
    }

    // MARK: - Scaled Font Size

    /// Returns a font size scaled according to the current preset
    func scaled(_ size: CGFloat) -> CGFloat {
        size * fontSizePreset.scaleFactor
    }

    func setZenModeEnabled(_ enabled: Bool) {
        guard enabled != isZenModeEnabled else { return }

        if enabled {
            lastLeftSidebarVisible = leftSidebarVisible
            lastRightSidebarVisible = rightSidebarVisible
            leftSidebarVisible = false
            rightSidebarVisible = false
            isZenModeEnabled = true
        } else {
            isZenModeEnabled = false
            leftSidebarVisible = lastLeftSidebarVisible
            rightSidebarVisible = lastRightSidebarVisible
        }
    }
}
