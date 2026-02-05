//
//  SessionLiveState.swift
//  unbound-macos
//
//  Per-session @Observable state machine.
//  Manages message state, streaming content, tool state, and daemon subscription
//  for a single session. Replaces ChatPanelViewModel with per-session isolation.
//
//  Uses IPC streaming subscription for real-time updates. The daemon pushes
//  events over the Unix socket connection.
//

import Foundation
import Logging

private let logger = Logger(label: "app.ui.chat")

// MARK: - Subscription State

enum SubscriptionState: Equatable {
    case idle
    case connecting
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
    var output: String?  // Live output for streaming display (e.g., Bash)
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
    private(set) var activeSubAgents: [ActiveSubAgent] = []
    private(set) var pendingPrompt: PendingPrompt?
    private(set) var toolHistory: [ToolHistoryEntry] = []

    // MARK: - Error State

    private(set) var showErrorAlert = false
    private(set) var errorAlertTitle: String = ""
    private(set) var errorAlertMessage: String = ""

    // MARK: - Private

    private var subscriptionTask: Task<Void, Never>?
    private var fetchDebounceTask: Task<Void, Never>?
    private var pendingSubAgentTools: [String: [ActiveTool]] = [:]

    // MARK: - Initialization

    init(sessionId: UUID, daemonClient: DaemonClient = .shared) {
        self.sessionId = sessionId
        self.daemonClient = daemonClient
    }

    deinit {
        logger.info("SessionLiveState deinit for session \(sessionId)")
        subscriptionTask?.cancel()
        fetchDebounceTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Activate this session: load messages and subscribe for real-time updates.
    /// Idempotent - returns immediately if already subscribed.
    func activate() async {
        let activateStart = CFAbsoluteTimeGetCurrent()

        guard subscriptionState != .subscribed, subscriptionState != .connecting else {
            return
        }

        subscriptionState = .connecting

        // Load messages first
        let loadStart = CFAbsoluteTimeGetCurrent()
        await loadMessages()
        let loadDuration = CFAbsoluteTimeGetCurrent() - loadStart
        logger.info("loadMessages took \(String(format: "%.3f", loadDuration))s")

        // Check initial Claude status
        await checkClaudeStatus()

        // Subscribe for real-time updates via IPC streaming
        let streamingClient = SessionStreamingClient(
            sessionId: sessionId.uuidString.lowercased()
        )

        do {
            let eventStream = try await streamingClient.subscribe()
            subscriptionState = .subscribed

            let totalDuration = CFAbsoluteTimeGetCurrent() - activateStart
            logger.info("activate() total: \(String(format: "%.3f", totalDuration))s for session \(sessionId)")

            // Start event handling task
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
            logger.error("Failed to subscribe: \(error)")
            subscriptionState = .disconnected
        }
    }

    /// Check Claude status from daemon.
    private func checkClaudeStatus() async {
        do {
            let status = try await daemonClient.getClaudeStatus(
                sessionId: sessionId.uuidString.lowercased()
            )
            claudeRunning = status.isRunning
        } catch {
            logger.debug("Failed to check Claude status: \(error)")
        }
    }

    /// Deactivate this session: disconnect subscription but keep cached state.
    func deactivate() {
        logger.info("Deactivating session \(sessionId)")
        subscriptionTask?.cancel()
        subscriptionTask = nil
        fetchDebounceTask?.cancel()
        fetchDebounceTask = nil
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

            // Parse messages on background thread to avoid blocking UI
            let parseSignpost = ChatPerformanceSignposts.beginInterval(
                "chat.loadMessages.parse",
                "incoming=\(daemonMessages.count)"
            )
            let parseStart = CFAbsoluteTimeGetCurrent()
            let parsedMessages = await Task.detached(priority: .userInitiated) {
                let parsed = daemonMessages.compactMap { ClaudeMessageParser.parseMessage($0) }
                return ChatMessageGrouper.groupSubAgentTools(messages: parsed)
            }.value
            let parseDuration = CFAbsoluteTimeGetCurrent() - parseStart
            logger.info("parse took \(String(format: "%.3f", parseDuration))s for \(parsedMessages.count) parsed messages")
            ChatPerformanceSignposts.endInterval(parseSignpost, "parsed=\(parsedMessages.count)")

            messages = parsedMessages
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
                for i in activeSubAgents.indices {
                    for j in activeSubAgents[i].childTools.indices {
                        if activeSubAgents[i].childTools[j].status == .running {
                            activeSubAgents[i].childTools[j].status = .failed
                        }
                    }
                    if activeSubAgents[i].status == .running {
                        activeSubAgents[i].status = .failed
                    }
                }

                // Mark pending sub-agent tools as failed and flush to standalone tools
                if !pendingSubAgentTools.isEmpty {
                    for (_, tools) in pendingSubAgentTools {
                        var failedTools = tools
                        for index in failedTools.indices {
                            if failedTools[index].status == .running {
                                failedTools[index].status = .failed
                            }
                        }
                        activeTools.append(contentsOf: failedTools)
                    }
                    pendingSubAgentTools.removeAll()
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
        activeSubAgents.removeAll()
        pendingSubAgentTools.removeAll()
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
        let fetchSignpost = ChatPerformanceSignposts.beginInterval(
            "chat.fetchMessages",
            "session=\(sessionId.uuidString)"
        )
        do {
            let daemonMessages = try await daemonClient.listMessages(
                sessionId: sessionId.uuidString.lowercased()
            )
            // Parse messages on background thread to avoid blocking UI
            let parsedMessages = await Task.detached(priority: .userInitiated) {
                let parsed = daemonMessages.compactMap { ClaudeMessageParser.parseMessage($0) }
                return ChatMessageGrouper.groupSubAgentTools(messages: parsed)
            }.value
            messages = parsedMessages
            ChatPerformanceSignposts.endInterval(fetchSignpost, "parsed=\(parsedMessages.count)")
        } catch {
            logger.error("Failed to fetch messages: \(error)")
            ChatPerformanceSignposts.endInterval(fetchSignpost, "error")
        }
    }

    // MARK: - Private: Event Handling

    private func handleDaemonEvent(_ event: DaemonEvent) {
        switch event.type {
        case .streamingChunk, .claudeStreaming:
            if let content: String = event.dataValue(for: "content") ?? event.dataValue(for: "chunk") {
                logger.debug("Received streaming chunk (\(content.count) chars) for session \(sessionId)")
                streamingContent = content
            }

        case .message:
            logger.info("Received message event for session \(sessionId)")
            streamingContent = nil
            debouncedFetchMessages()

        case .claudeEvent, .claudeSystem, .claudeAssistant, .claudeUser, .claudeResult:
            // Claude events contain raw JSON that needs to be parsed
            if let raw = event.rawClaudeEvent {
                handleClaudeEvent(raw)
            } else {
                // For new event types, the data IS the parsed JSON already
                // Convert AnyCodableValue map to plain values for serialization
                var plainData: [String: Any] = [:]
                for (key, value) in event.data {
                    plainData[key] = value.value
                }

                // Check if this is an empty event or ping
                if plainData.isEmpty {
                    logger.debug("Received empty claude event data for session \(sessionId), type=\(event.type)")
                    return
                }

                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: plainData)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        handleClaudeEvent(jsonString)
                    }
                } catch {
                    logger.warning("Failed to serialize claude event data for session \(sessionId): \(error.localizedDescription)")
                }
            }

        case .statusChange:
            if let status: String = event.dataValue(for: "status") {
                logger.info("Received status change: \(status) for session \(sessionId)")
                claudeRunning = (status == "running")
                if !claudeRunning {
                    moveToolsToHistory()
                    streamingContent = nil
                    debouncedFetchMessages()
                }
            }

        case .terminalOutput, .terminalFinished:
            logger.debug("Received terminal event for session \(sessionId)")

        case .initialState:
            logger.info("Received initial state for session \(sessionId)")
            debouncedFetchMessages()

        case .ping:
            break

        case .authStateChanged, .sessionCreated, .sessionDeleted:
            // Global events, not relevant for per-session state
            break
        }
    }

    private func handleClaudeEvent(_ json: String) {
        guard let data = json.data(using: .utf8) else {
            logger.warning("Failed to convert claude event to data for session \(sessionId)")
            return
        }

        let parsed: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("Claude event is not a dictionary for session \(sessionId): \(json.prefix(200))")
                return
            }
            parsed = dict
        } catch {
            logger.warning("Failed to parse claude event JSON for session \(sessionId): \(error.localizedDescription), raw: \(json.prefix(200))")
            return
        }

        guard let type = parsed["type"] as? String else {
            logger.warning("Claude event missing 'type' field for session \(sessionId): \(json.prefix(200))")
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
        }
    }

#if DEBUG
    /// Testing hook: ingest a raw Claude JSON event string and update tool state.
    func ingestClaudeEventForTests(_ json: String) {
        handleClaudeEvent(json)
    }
#endif

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

        let messageParent = json["parent_tool_use_id"] as? String
        var textParts: [String] = []
        for block in contentBlocks {
            if let blockType = block["type"] as? String {
                switch blockType {
                case "text":
                    if let text = block["text"] as? String {
                        textParts.append(text)
                    }
                case "tool_use":
                    handleToolUseBlock(block, parentOverride: messageParent)
                default:
                    break
                }
            }
        }

        if !textParts.isEmpty {
            streamingContent = textParts.joined()
        }
    }

    private func handleToolUseBlock(_ block: [String: Any], parentOverride: String? = nil) {
        guard let id = block["id"] as? String,
              let name = block["name"] as? String else {
            return
        }

        logger.debug("Tool use: \(name) (id=\(id)) for session \(sessionId)")

        let input = block["input"] as? [String: Any]
        let parentToolUseId = (block["parent_tool_use_id"] as? String) ?? parentOverride

        // Check for Task (sub-agent)
        if name == "Task" {
            if toolHistory.contains(where: { $0.subAgent?.id == id }) {
                logger.debug("Sub-agent \(id) already in history, skipping creation")
                return
            }

            let subagentType = input?["subagent_type"] as? String ?? "unknown"
            let description = input?["description"] as? String ?? ""

            var subAgent = ActiveSubAgent(
                id: id,
                subagentType: subagentType,
                description: description,
                childTools: [],
                status: .running
            )

            if let pendingTools = pendingSubAgentTools.removeValue(forKey: id) {
                subAgent.childTools.append(contentsOf: pendingTools)
            }

            activeSubAgents.append(subAgent)
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

        if let parentToolUseId {
            if let index = activeSubAgents.firstIndex(where: { $0.id == parentToolUseId }) {
                activeSubAgents[index].childTools.append(tool)
            } else {
                pendingSubAgentTools[parentToolUseId, default: []].append(tool)
            }
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

        for subAgentIndex in activeSubAgents.indices {
            if let childIndex = activeSubAgents[subAgentIndex].childTools.firstIndex(where: { $0.id == toolUseId }) {
                activeSubAgents[subAgentIndex].childTools[childIndex].status = status
                return
            }

            if toolUseId == activeSubAgents[subAgentIndex].id {
                activeSubAgents[subAgentIndex].status = status
                return
            }
        }

        if !pendingSubAgentTools.isEmpty {
            for (parentId, tools) in pendingSubAgentTools {
                if let toolIndex = tools.firstIndex(where: { $0.id == toolUseId }) {
                    var updatedTools = tools
                    updatedTools[toolIndex].status = status
                    pendingSubAgentTools[parentId] = updatedTools
                    return
                }
            }
        }
    }

    // MARK: - Private: Tool History

    private func moveToolsToHistory() {
        let hasPendingTools = !pendingSubAgentTools.isEmpty
        guard !activeTools.isEmpty || !activeSubAgents.isEmpty || hasPendingTools else { return }

        // Flush any pending sub-agent tools into standalone tools
        if hasPendingTools {
            for (_, tools) in pendingSubAgentTools {
                activeTools.append(contentsOf: tools)
            }
            pendingSubAgentTools.removeAll()
        }

        let afterIndex = messages.count.advanced(by: -1)

        for subAgent in activeSubAgents {
            if toolHistory.contains(where: { $0.subAgent?.id == subAgent.id }) {
                logger.debug("Sub-agent \(subAgent.id) already in history, skipping")
                continue
            }

            toolHistory.append(ToolHistoryEntry(
                tools: [],
                subAgent: subAgent,
                afterMessageIndex: afterIndex
            ))
        }

        if !activeTools.isEmpty {
            toolHistory.append(ToolHistoryEntry(
                tools: activeTools,
                subAgent: nil,
                afterMessageIndex: afterIndex
            ))
        }

        activeTools.removeAll()
        activeSubAgents.removeAll()
    }

    // MARK: - Private: Message Parsing
}
