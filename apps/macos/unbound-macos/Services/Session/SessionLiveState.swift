//
//  SessionLiveState.swift
//  unbound-macos
//
//  Per-session @Observable state machine.
//  Manages message state, streaming content, tool state, and daemon subscription
//  for a single session. Replaces ChatPanelViewModel with per-session isolation.
//
//  Each instance owns a SessionSubscription (shared memory consumer)
//  so multiple sessions can stream events concurrently with low latency.
//

import Foundation
import Logging

private let logger = Logger(label: "app.ui.chat")

// MARK: - Subscription State

enum SubscriptionState: Equatable {
    case idle
    case subscribing
    case subscribed
    case disconnected
}

// MARK: - Active Tool State

/// A tool that is currently running.
struct ActiveTool: Identifiable {
    let id: String  // tool_use_id
    let name: String
    let inputPreview: String?
    var status: ToolStatus
}

/// A sub-agent (Task tool) that is running with child tools.
struct ActiveSubAgent: Identifiable {
    let id: String  // tool_use_id
    let subagentType: String
    let description: String
    var childTools: [ActiveTool]
    var status: ToolStatus
}

/// A pending prompt (AskUserQuestion) waiting for response.
struct PendingPrompt: Identifiable {
    let id: String  // tool_use_id
    let question: String
    let header: String?
    let options: [QuestionOption]
    let allowsMultiSelect: Bool
    var selectedOption: Int
    var textResponse: String?
}

/// Entry in the tool history after completion.
struct ToolHistoryEntry: Identifiable {
    let id = UUID()
    let tools: [ActiveTool]
    let subAgent: ActiveSubAgent?
    let afterMessageIndex: Int
}

// MARK: - Session Live State

@Observable
class SessionLiveState {

    // MARK: - Identity

    let sessionId: UUID

    // MARK: - Dependencies

    private let daemonClient: DaemonClient

    // MARK: - Subscription State

    private(set) var subscriptionState: SubscriptionState = .idle

    // MARK: - Message State

    private(set) var messages: [ChatMessage] = []
    private(set) var isLoadingMessages = false

    // MARK: - Streaming State

    private(set) var streamingContent: String?
    private(set) var claudeRunning: Bool = false

    // MARK: - Tool State

    private(set) var activeTools: [ActiveTool] = []
    private(set) var activeSubAgent: ActiveSubAgent?
    private(set) var pendingPrompt: PendingPrompt?
    private(set) var toolHistory: [ToolHistoryEntry] = []

    // MARK: - Error State

    private(set) var showErrorAlert = false
    private(set) var errorAlertTitle: String = ""
    private(set) var errorAlertMessage: String = ""

    // MARK: - Private

    private var subscription: SessionSubscription?
    private var subscriptionTask: Task<Void, Never>?
    private var fetchDebounceTask: Task<Void, Never>?

    // MARK: - Initialization

    init(sessionId: UUID, daemonClient: DaemonClient = .shared) {
        self.sessionId = sessionId
        self.daemonClient = daemonClient
    }

    deinit {
        logger.info("SessionLiveState deinit for session \(sessionId)")
        subscriptionTask?.cancel()
        fetchDebounceTask?.cancel()
        subscription?.disconnect()
    }

    // MARK: - Lifecycle

    /// Activate this session: subscribe for events and load messages.
    /// Idempotent - returns immediately if already subscribed.
    func activate() async {
        let activateStart = CFAbsoluteTimeGetCurrent()

        guard subscriptionState != .subscribed, subscriptionState != .subscribing else {
            return
        }

        subscriptionState = .subscribing

        // Load messages first
        let loadStart = CFAbsoluteTimeGetCurrent()
        await loadMessages()
        let loadDuration = CFAbsoluteTimeGetCurrent() - loadStart
        logger.info("loadMessages took \(String(format: "%.3f", loadDuration))s")

        // Then subscribe for real-time updates
        let subStart = CFAbsoluteTimeGetCurrent()
        do {
            let sub = SessionSubscription(
                sessionId: sessionId.uuidString.lowercased()
            )
            self.subscription = sub

            let eventStream = try await sub.subscribe()
            let subDuration = CFAbsoluteTimeGetCurrent() - subStart
            logger.info("subscribe took \(String(format: "%.3f", subDuration))s")

            subscriptionState = .subscribed

            let totalDuration = CFAbsoluteTimeGetCurrent() - activateStart
            logger.info("activate() total: \(String(format: "%.3f", totalDuration))s for session \(sessionId)")

            // Start polling events
            subscriptionTask = Task { [weak self] in
                logger.debug("Event loop started for session \(sessionId)")
                for await event in eventStream {
                    await MainActor.run {
                        self?.handleDaemonEvent(event)
                    }
                }

                // Stream ended
                logger.info("Event stream ended for session \(sessionId)")
                await MainActor.run {
                    if self?.subscriptionState == .subscribed {
                        self?.subscriptionState = .disconnected
                        logger.warning("Session \(sessionId) disconnected (stream ended)")
                    }
                }
            }
        } catch {
            logger.warning("Failed to subscribe to session \(sessionId): \(error)")
            subscriptionState = .disconnected
        }
    }

    /// Deactivate this session: disconnect subscription but keep cached state.
    func deactivate() {
        logger.info("Deactivating session \(sessionId)")
        subscriptionTask?.cancel()
        subscriptionTask = nil
        fetchDebounceTask?.cancel()
        fetchDebounceTask = nil
        subscription?.disconnect()
        subscription = nil
        subscriptionState = .idle
    }

    // MARK: - Message Loading

    func loadMessages() async {
        guard !claudeRunning else { return }

        isLoadingMessages = true
        defer { isLoadingMessages = false }

        do {
            let fetchStart = CFAbsoluteTimeGetCurrent()
            let daemonMessages = try await daemonClient.listMessages(
                sessionId: sessionId.uuidString.lowercased()
            )
            let fetchDuration = CFAbsoluteTimeGetCurrent() - fetchStart
            logger.info("daemon fetch took \(String(format: "%.3f", fetchDuration))s for \(daemonMessages.count) messages")

            let parseStart = CFAbsoluteTimeGetCurrent()
            messages = daemonMessages.compactMap { parseMessage($0) }
            let parseDuration = CFAbsoluteTimeGetCurrent() - parseStart
            logger.info("parse took \(String(format: "%.3f", parseDuration))s for \(messages.count) parsed messages")
        } catch {
            logger.error("Failed to load messages: \(error)")
            messages = []
        }
    }

    // MARK: - Send Message

    func sendMessage(
        _ text: String,
        session: Session,
        workspacePath: String,
        modelIdentifier: String?
    ) async {
        logger.info("sendMessage called for session \(session.id)")

        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        // Add user message to local UI immediately
        let userMessage = ChatMessage(role: .user, text: messageText)
        messages.append(userMessage)

        // Mark Claude as running (status updates come via subscription events)
        claudeRunning = true

        do {
            try await daemonClient.sendToClaude(
                sessionId: session.id.uuidString.lowercased(),
                content: messageText,
                workingDirectory: workspacePath,
                modelIdentifier: modelIdentifier
            )

            logger.info("Message sent to Claude via daemon")

            // Fetch updated messages
            await fetchMessages()
        } catch {
            logger.error("Failed to send message: \(error)")
            claudeRunning = false

            let errorMessage = ChatMessage(
                role: .assistant,
                content: [.error(ErrorContent(
                    message: "Failed to send message",
                    details: error.localizedDescription
                ))]
            )
            messages.append(errorMessage)
        }
    }

    // MARK: - Cancel Stream

    func cancelStream() {
        Task {
            do {
                try await daemonClient.stopClaude(
                    sessionId: sessionId.uuidString.lowercased()
                )
                claudeRunning = false
                streamingContent = nil

                // Mark active tools as failed
                for i in activeTools.indices {
                    if activeTools[i].status == .running {
                        activeTools[i].status = .failed
                    }
                }
                if var subAgent = activeSubAgent {
                    for i in subAgent.childTools.indices {
                        if subAgent.childTools[i].status == .running {
                            subAgent.childTools[i].status = .failed
                        }
                    }
                    subAgent.status = .failed
                    activeSubAgent = subAgent
                }

                moveToolsToHistory()
            } catch {
                logger.error("Failed to cancel stream: \(error)")
            }
        }
    }

    // MARK: - Question Response

    func respondToPrompt(_ response: String) {
        guard pendingPrompt != nil else { return }

        pendingPrompt = nil

        Task {
            do {
                try await daemonClient.sendToClaude(
                    sessionId: sessionId.uuidString.lowercased(),
                    content: response
                )
            } catch {
                logger.error("Failed to respond to prompt: \(error)")
            }
        }
    }

    // MARK: - Error Handling

    func dismissErrorAlert() {
        showErrorAlert = false
        errorAlertTitle = ""
        errorAlertMessage = ""
    }

    // MARK: - Tool State Management

    func clearToolState() {
        activeTools.removeAll()
        activeSubAgent = nil
        toolHistory.removeAll()
        streamingContent = nil
        pendingPrompt = nil
    }

    // MARK: - Private: Message Fetching

    /// Debounced fetch: coalesces rapid message events into a single fetch.
    private func debouncedFetchMessages() {
        fetchDebounceTask?.cancel()
        fetchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            await self.fetchMessages()
        }
    }

    private func fetchMessages() async {
        do {
            let daemonMessages = try await daemonClient.listMessages(
                sessionId: sessionId.uuidString.lowercased()
            )
            messages = daemonMessages.compactMap { parseMessage($0) }
        } catch {
            logger.error("Failed to fetch messages: \(error)")
        }
    }

    // MARK: - Private: Event Handling

    private func handleDaemonEvent(_ event: DaemonEvent) {
        switch event.type {
        case .streamingChunk, .claudeStreaming:
            if let content = event.streamingContent {
                logger.debug("Received streaming chunk (\(content.count) chars) for session \(sessionId)")
                streamingContent = content
            }

        case .message:
            logger.info("Received message event for session \(sessionId)")
            streamingContent = nil
            debouncedFetchMessages()

        case .claudeEvent, .claudeSystem, .claudeAssistant, .claudeUser, .claudeResult:
            // All Claude events contain raw JSON that needs to be parsed
            if let raw = event.rawClaudeEvent {
                handleClaudeEvent(raw)
            } else {
                // For new event types, the data IS the parsed JSON already
                // Convert it back to JSON string for handleClaudeEvent
                if let jsonData = try? JSONSerialization.data(withJSONObject: event.data.mapValues { $0.value }),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    handleClaudeEvent(jsonString)
                }
            }

        case .statusChange:
            if let status = event.statusValue {
                logger.info("Received status change: \(status) for session \(sessionId)")
                claudeRunning = (status == "running")
                if !claudeRunning {
                    moveToolsToHistory()
                    streamingContent = nil
                }
            }

        case .terminalOutput, .terminalFinished:
            logger.debug("Received terminal event for session \(sessionId)")
            break

        case .initialState:
            logger.info("Received initial state for session \(sessionId)")
            debouncedFetchMessages()

        case .ping:
            break
        }
    }

    // MARK: - Private: Claude Event Parsing

    private func handleClaudeEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = parsed["type"] as? String else {
            logger.warning("Failed to parse claude event JSON for session \(sessionId)")
            return
        }

        logger.debug("Received claude event type=\(type) for session \(sessionId)")

        switch type {
        case "assistant":
            handleAssistantEvent(parsed)
        case "user":
            handleUserEvent(parsed)
        case "result":
            handleResultEvent(parsed)
        case "system":
            handleSystemEvent(parsed)
        default:
            logger.debug("Unhandled claude event type=\(type) for session \(sessionId)")
            break
        }
    }

    private func handleAssistantEvent(_ json: [String: Any]) {
        // Detect externally-triggered Claude run (e.g. from TUI)
        if !claudeRunning {
            logger.info("Detected external Claude run for session \(sessionId), setting claudeRunning=true")
            claudeRunning = true
        }

        guard let message = json["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return
        }

        var textParts: [String] = []
        for block in contentBlocks {
            if let blockType = block["type"] as? String {
                switch blockType {
                case "text":
                    if let text = block["text"] as? String {
                        textParts.append(text)
                    }
                case "tool_use":
                    handleToolUseBlock(block)
                default:
                    break
                }
            }
        }

        if !textParts.isEmpty {
            streamingContent = textParts.joined()
        }
    }

    private func handleToolUseBlock(_ block: [String: Any]) {
        guard let id = block["id"] as? String,
              let name = block["name"] as? String else {
            return
        }

        logger.debug("Tool use: \(name) (id=\(id)) for session \(sessionId)")

        let input = block["input"] as? [String: Any]

        // Check for Task (sub-agent)
        if name == "Task" {
            // Don't recreate sub-agent if it's already archived in history
            if toolHistory.contains(where: { $0.subAgent?.id == id }) {
                logger.debug("Sub-agent \(id) already in history, skipping creation")
                return
            }

            let subagentType = input?["subagent_type"] as? String ?? "unknown"
            let description = input?["description"] as? String ?? ""

            activeSubAgent = ActiveSubAgent(
                id: id,
                subagentType: subagentType,
                description: description,
                childTools: [],
                status: .running
            )
            return
        }

        // Check for AskUserQuestion (prompt)
        if name == "AskUserQuestion" {
            if let questions = input?["questions"] as? [[String: Any]],
               let firstQuestion = questions.first {
                let questionText = firstQuestion["question"] as? String ?? ""
                let header = firstQuestion["header"] as? String
                let multiSelect = firstQuestion["multi_select"] as? Bool ?? false
                let optionsData = firstQuestion["options"] as? [[String: Any]] ?? []

                let options = optionsData.map { opt in
                    QuestionOption(
                        label: opt["label"] as? String ?? "",
                        description: opt["description"] as? String
                    )
                }

                pendingPrompt = PendingPrompt(
                    id: id,
                    question: questionText,
                    header: header,
                    options: options,
                    allowsMultiSelect: multiSelect,
                    selectedOption: 0
                )
            }
            return
        }

        // Regular tool
        let inputPreview = createToolInputPreview(name: name, input: input)
        let tool = ActiveTool(id: id, name: name, inputPreview: inputPreview, status: .running)

        if activeSubAgent != nil {
            activeSubAgent?.childTools.append(tool)
        } else {
            activeTools.append(tool)
        }
    }

    private func createToolInputPreview(name: String, input: [String: Any]?) -> String? {
        guard let input else { return nil }

        switch name {
        case "Read", "Write", "Edit":
            return input["file_path"] as? String
        case "Bash":
            if let cmd = input["command"] as? String {
                return String(cmd.prefix(50))
            }
        case "Glob", "Grep":
            return input["pattern"] as? String
        case "Task":
            return input["description"] as? String
        case "WebFetch", "WebSearch":
            return input["url"] as? String ?? input["query"] as? String
        default:
            break
        }
        return nil
    }

    private func handleUserEvent(_ json: [String: Any]) {
        guard let message = json["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return
        }

        for block in contentBlocks {
            if let blockType = block["type"] as? String,
               blockType == "tool_result",
               let toolUseId = block["tool_use_id"] as? String {
                let isError = block["is_error"] as? Bool ?? false
                let status: ToolStatus = isError ? .failed : .completed
                logger.debug("Tool result for \(toolUseId): \(status) (error=\(isError))")
                updateToolStatus(toolUseId: toolUseId, status: status)
            }
        }
    }

    private func handleResultEvent(_ json: [String: Any]) {
        logger.info("Claude run completed for session \(sessionId), fetching final messages")
        claudeRunning = false
        streamingContent = nil
        moveToolsToHistory()
        pendingPrompt = nil
        debouncedFetchMessages()
    }

    private func handleSystemEvent(_ json: [String: Any]) {
        if let subtype = json["subtype"] as? String, subtype == "init" {
            logger.debug("Session initialized")
        }
    }

    private func updateToolStatus(toolUseId: String, status: ToolStatus) {
        if let index = activeTools.firstIndex(where: { $0.id == toolUseId }) {
            activeTools[index].status = status
            return
        }

        if let subAgent = activeSubAgent,
           let index = subAgent.childTools.firstIndex(where: { $0.id == toolUseId }) {
            activeSubAgent?.childTools[index].status = status

            if toolUseId == subAgent.id {
                activeSubAgent?.status = status
            }
            return
        }
    }

    private func moveToolsToHistory() {
        guard !activeTools.isEmpty || activeSubAgent != nil else { return }

        // Check if this sub-agent is already in history (prevents duplicate entries
        // when both statusChange and result events trigger moveToolsToHistory)
        if let subAgent = activeSubAgent,
           toolHistory.contains(where: { $0.subAgent?.id == subAgent.id }) {
            logger.debug("Sub-agent \(subAgent.id) already in history, clearing active state only")
            activeTools.removeAll()
            activeSubAgent = nil
            return
        }

        toolHistory.append(ToolHistoryEntry(
            tools: activeTools,
            subAgent: activeSubAgent,
            afterMessageIndex: messages.count.advanced(by: -1)
        ))
        activeTools.removeAll()
        activeSubAgent = nil
    }

    // MARK: - Private: Message Parsing

    private func parseMessage(_ daemonMessage: DaemonMessage) -> ChatMessage? {
        guard let content = daemonMessage.content, !content.isEmpty else { return nil }

        let messageDate = daemonMessage.date ?? Date()

        guard let contentData = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let type = json["type"] as? String else {
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .user,
                text: content,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        }

        switch type {
        case "assistant":
            guard let messageContent = parseClaudeContent(json) else { return nil }
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .assistant,
                content: messageContent,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        case "result":
            let isError = json["is_error"] as? Bool ?? false
            if isError, let errorText = json["result"] as? String {
                return ChatMessage(
                    id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                    role: .system,
                    text: "Error: \(errorText)",
                    timestamp: messageDate,
                    sequenceNumber: daemonMessage.sequenceNumber
                )
            }
            return nil
        case "system", "user":
            return nil
        default:
            return nil
        }
    }

    private func parseClaudeContent(_ json: [String: Any]) -> [MessageContent]? {
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return nil
            }

            var content: [MessageContent] = []
            for block in contentBlocks {
                if let blockType = block["type"] as? String {
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String {
                            content.append(.text(TextContent(text: text)))
                        }
                    case "tool_use":
                        if let id = block["id"] as? String,
                           let name = block["name"] as? String {
                            let inputJson = (block["input"] as? [String: Any]).flatMap { dict in
                                try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
                            }.flatMap { String(data: $0, encoding: .utf8) }

                            content.append(.toolUse(ToolUse(
                                toolUseId: id,
                                toolName: name,
                                input: inputJson,
                                status: .completed
                            )))
                        }
                    default:
                        break
                    }
                }
            }
            return content.isEmpty ? nil : content

        case "user":
            guard let message = json["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return nil
            }

            var content: [MessageContent] = []
            for block in contentBlocks {
                if let blockType = block["type"] as? String, blockType == "tool_result" {
                    if let toolContent = block["content"] as? String {
                        content.append(.text(TextContent(text: toolContent)))
                    }
                }
            }
            return content.isEmpty ? nil : content

        default:
            return nil
        }
    }
}
