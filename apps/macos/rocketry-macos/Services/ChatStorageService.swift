//
//  ChatStorageService.swift
//  rocketry-macos
//
//  Persists chat tabs per workspace
//

import Foundation

// MARK: - Chat Store (for JSON persistence)

struct ChatStore: Codable {
    var tabsByWorkspace: [String: [ChatTab]]  // Key is workspace UUID string
    let version: Int

    init(tabsByWorkspace: [String: [ChatTab]] = [:], version: Int = 1) {
        self.tabsByWorkspace = tabsByWorkspace
        self.version = version
    }
}

// MARK: - Chat Storage Service

@Observable
class ChatStorageService {
    private(set) var tabsByWorkspace: [UUID: [ChatTab]] = [:]
    private(set) var selectedTabIdByWorkspace: [UUID: UUID] = [:]

    /// Storage directory for app configuration
    private var appSupportURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Rocketry", isDirectory: true)
    }

    /// Path to chat-history.json
    private var storageURL: URL {
        appSupportURL.appendingPathComponent("chat-history.json")
    }

    // MARK: - Persistence

    /// Load chat history from disk
    func load() throws {
        // Ensure app support directory exists
        try ensureAppSupportDirectoryExists()

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            tabsByWorkspace = [:]
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(ChatStore.self, from: data)

        // Convert string keys back to UUIDs
        tabsByWorkspace = [:]
        for (keyString, tabs) in store.tabsByWorkspace {
            if let uuid = UUID(uuidString: keyString) {
                tabsByWorkspace[uuid] = tabs
            }
        }
    }

    /// Save chat history to disk
    func save() throws {
        try ensureAppSupportDirectoryExists()

        // Convert UUID keys to strings for JSON
        var stringKeyedTabs: [String: [ChatTab]] = [:]
        for (uuid, tabs) in tabsByWorkspace {
            stringKeyedTabs[uuid.uuidString] = tabs
        }

        let store = ChatStore(tabsByWorkspace: stringKeyedTabs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store)
        try data.write(to: storageURL, options: .atomic)
    }

    /// Ensure app support directory exists
    private func ensureAppSupportDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: appSupportURL.path) {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Tab Management

    /// Get tabs for a workspace
    func tabs(for workspaceId: UUID) -> [ChatTab] {
        tabsByWorkspace[workspaceId] ?? []
    }

    /// Set tabs for a workspace
    func setTabs(_ tabs: [ChatTab], for workspaceId: UUID) {
        tabsByWorkspace[workspaceId] = tabs
        try? save()
    }

    /// Get selected tab ID for a workspace
    func selectedTabId(for workspaceId: UUID) -> UUID? {
        selectedTabIdByWorkspace[workspaceId]
    }

    /// Set selected tab ID for a workspace
    func setSelectedTabId(_ tabId: UUID?, for workspaceId: UUID) {
        selectedTabIdByWorkspace[workspaceId] = tabId
    }

    /// Initialize tabs for workspace if needed (creates default tab)
    func initializeTabsIfNeeded(for workspaceId: UUID) {
        if tabsByWorkspace[workspaceId] == nil || tabsByWorkspace[workspaceId]?.isEmpty == true {
            let newTab = ChatTab(title: "New chat")
            tabsByWorkspace[workspaceId] = [newTab]
            selectedTabIdByWorkspace[workspaceId] = newTab.id
            try? save()
        } else if selectedTabIdByWorkspace[workspaceId] == nil {
            selectedTabIdByWorkspace[workspaceId] = tabsByWorkspace[workspaceId]?.first?.id
        }
    }

    /// Add a new tab to workspace
    func addTab(to workspaceId: UUID) -> ChatTab {
        let newTab = ChatTab(title: "New chat")
        if tabsByWorkspace[workspaceId] == nil {
            tabsByWorkspace[workspaceId] = []
        }
        tabsByWorkspace[workspaceId]?.append(newTab)
        selectedTabIdByWorkspace[workspaceId] = newTab.id
        try? save()
        return newTab
    }

    /// Close a tab
    func closeTab(_ tabId: UUID, in workspaceId: UUID) {
        guard var tabs = tabsByWorkspace[workspaceId],
              let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            return
        }

        tabs.remove(at: index)
        tabsByWorkspace[workspaceId] = tabs

        // Select another tab if the closed one was selected
        if selectedTabIdByWorkspace[workspaceId] == tabId {
            if !tabs.isEmpty {
                selectedTabIdByWorkspace[workspaceId] = tabs[max(0, index - 1)].id
            } else {
                selectedTabIdByWorkspace[workspaceId] = nil
            }
        }

        try? save()
    }

    /// Update a tab's messages
    func updateTabMessages(_ tabId: UUID, in workspaceId: UUID, messages: [ChatMessage]) {
        guard var tabs = tabsByWorkspace[workspaceId],
              let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            return
        }

        tabs[index].messages = messages
        tabsByWorkspace[workspaceId] = tabs
        try? save()
    }

    /// Get current tab for a workspace
    func currentTab(for workspaceId: UUID) -> ChatTab? {
        guard let selectedId = selectedTabIdByWorkspace[workspaceId],
              let tabs = tabsByWorkspace[workspaceId] else {
            return nil
        }
        return tabs.first { $0.id == selectedId }
    }

    /// Delete all chat history for a workspace
    func deleteHistory(for workspaceId: UUID) {
        tabsByWorkspace.removeValue(forKey: workspaceId)
        selectedTabIdByWorkspace.removeValue(forKey: workspaceId)
        try? save()
    }
}
