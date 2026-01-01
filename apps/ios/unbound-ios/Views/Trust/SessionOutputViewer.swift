//
//  SessionOutputViewer.swift
//  unbound-ios
//
//  Real-time Claude session output viewer with remote control capabilities.
//  Displays streaming output and provides pause/resume/stop controls.
//

import SwiftUI
import Combine

struct SessionOutputViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sessionControlService) private var sessionControl
    @Environment(\.relayService) private var relayService

    let session: ControlledSession

    @State private var messages: [SessionMessage] = []
    @State private var currentTypingContent = ""
    @State private var isTyping = false
    @State private var inputText = ""
    @State private var sessionStatus: SessionStatus
    @State private var showControls = true
    @State private var showInputField = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var cancellables = Set<AnyCancellable>()

    init(session: ControlledSession) {
        self.session = session
        self._sessionStatus = State(initialValue: session.status)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header info bar
                    sessionInfoBar

                    // Messages list
                    messagesScrollView

                    // Typing indicator
                    if isTyping {
                        typingIndicator
                    }

                    // Input field (when enabled)
                    if showInputField {
                        inputBar
                    }

                    // Control bar
                    if showControls {
                        controlBar
                    }
                }
            }
            .navigationTitle(session.repositoryName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showInputField.toggle()
                        } label: {
                            Label(
                                showInputField ? "Hide Input" : "Show Input",
                                systemImage: showInputField ? "keyboard.chevron.compact.down" : "keyboard"
                            )
                        }

                        Button {
                            showControls.toggle()
                        } label: {
                            Label(
                                showControls ? "Hide Controls" : "Show Controls",
                                systemImage: showControls ? "eye.slash" : "eye"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            Task { await stopSession() }
                        } label: {
                            Label("End Session", systemImage: "stop.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                startObserving()
            }
            .onDisappear {
                stopObserving()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }

    // MARK: - Views

    private var sessionInfoBar: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Status indicator
            HStack(spacing: AppTheme.spacingXS) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(sessionStatus.displayName)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(statusColor.opacity(0.1))
            .cornerRadius(8)

            Spacer()

            // Device and branch info
            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: "laptopcomputer")
                    .font(.caption)
                Text(session.executorDeviceName)
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.textSecondary)

            Text("•")
                .foregroundStyle(AppTheme.textTertiary)

            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text(session.branchName)
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.spacingS)
        .background(AppTheme.backgroundSecondary)
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.spacingM) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Current typing content
                    if !currentTypingContent.isEmpty {
                        MessageBubble(
                            message: SessionMessage(
                                id: "typing",
                                role: .assistant,
                                content: currentTypingContent,
                                timestamp: Date()
                            )
                        )
                        .opacity(0.8)
                        .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo(messages.last?.id ?? "typing", anchor: .bottom)
                }
            }
            .onChange(of: currentTypingContent) {
                withAnimation {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: AppTheme.spacingS) {
            TypingDots()
            Text("Claude is typing...")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.backgroundSecondary)
    }

    private var inputBar: some View {
        HStack(spacing: AppTheme.spacingS) {
            TextField("Send a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppTheme.spacingM)
                .padding(.vertical, AppTheme.spacingS)
                .background(AppTheme.backgroundSecondary)
                .cornerRadius(20)
                .lineLimit(1...5)

            Button {
                sendInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.isEmpty ? AppTheme.textTertiary : AppTheme.accent)
            }
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.spacingS)
        .background(.ultraThinMaterial)
    }

    private var controlBar: some View {
        HStack(spacing: AppTheme.spacingL) {
            // Pause/Resume button
            Button {
                Task {
                    if sessionStatus == .paused {
                        await resumeSession()
                    } else {
                        await pauseSession()
                    }
                }
            } label: {
                VStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: sessionStatus == .paused ? "play.fill" : "pause.fill")
                        .font(.title2)
                    Text(sessionStatus == .paused ? "Resume" : "Pause")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!sessionStatus.isRunning)

            // Stop button
            Button {
                Task { await stopSession() }
            } label: {
                VStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                    Text("Stop")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.red)
            }
            .disabled(!sessionStatus.isRunning)

            // Duration
            VStack(spacing: AppTheme.spacingXS) {
                Text(session.durationText)
                    .font(.title3.monospacedDigit())
                Text("Duration")
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        switch sessionStatus {
        case .active: return .green
        case .paused: return .orange
        case .ended: return .gray
        case .error: return .red
        }
    }

    // MARK: - Actions

    private func startObserving() {
        Task {
            do {
                try await sessionControl.watchSession(session.id)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        // Subscribe to events
        sessionControl.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [self] event in
                handleEvent(event)
            }
            .store(in: &cancellables)
    }

    private func stopObserving() {
        try? sessionControl.stopWatching()
    }

    private func handleEvent(_ event: SessionControlEvent) {
        switch event {
        case .contentUpdate(let sessionId, let content):
            guard sessionId == session.id else { return }
            currentTypingContent += content

        case .typingStateChanged(let sessionId, let typing):
            guard sessionId == session.id else { return }
            isTyping = typing
            if !typing && !currentTypingContent.isEmpty {
                // Commit typing content to messages
                messages.append(SessionMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: currentTypingContent,
                    timestamp: Date()
                ))
                currentTypingContent = ""
            }

        case .sessionUpdated(let updatedSession):
            guard updatedSession.id == session.id else { return }
            sessionStatus = updatedSession.status

        case .controlSuccess(let sessionId, let action):
            guard sessionId == session.id else { return }
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            switch action {
            case .pause:
                sessionStatus = .paused
            case .resume:
                sessionStatus = .active
            case .stop:
                sessionStatus = .ended
            case .input:
                break
            }

        case .controlFailed(let sessionId, _, let reason):
            guard sessionId == session.id else { return }
            errorMessage = reason
            showError = true

        default:
            break
        }
    }

    private func pauseSession() async {
        do {
            _ = try await sessionControl.pauseSession()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func resumeSession() async {
        do {
            _ = try await sessionControl.resumeSession()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func stopSession() async {
        do {
            _ = try await sessionControl.stopSession()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func sendInput() {
        guard !inputText.isEmpty else { return }

        let content = inputText
        inputText = ""

        // Add user message
        messages.append(SessionMessage(
            id: UUID().uuidString,
            role: .user,
            content: content,
            timestamp: Date()
        ))

        Task {
            do {
                _ = try await sessionControl.sendInput(content)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Supporting Types

struct SessionMessage: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolUse: ToolUseInfo?

    enum MessageRole {
        case user
        case assistant
        case system
    }

    struct ToolUseInfo {
        let name: String
        let status: String
        let duration: TimeInterval?
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: SessionMessage

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            if message.role == .assistant {
                // Claude avatar
                Circle()
                    .fill(AppTheme.accent.opacity(0.1))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: AppTheme.spacingXS) {
                // Content
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, AppTheme.spacingM)
                    .padding(.vertical, AppTheme.spacingS)
                    .background(
                        message.role == .user
                            ? AppTheme.accent.opacity(0.1)
                            : AppTheme.backgroundSecondary
                    )
                    .cornerRadius(16)

                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                // User avatar
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
            }
        }
    }
}

// MARK: - Typing Dots

struct TypingDots: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppTheme.textSecondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.3)
                        .repeatForever()
                        .delay(Double(index) * 0.1),
                        value: animationPhase
                    )
            }
        }
        .onAppear {
            animationPhase = 2
        }
    }
}

// MARK: - Preview

#Preview {
    SessionOutputViewer(
        session: ControlledSession(
            id: UUID().uuidString,
            executorDeviceId: "device-123",
            executorDeviceName: "MacBook Pro",
            repositoryName: "unbound-ios",
            branchName: "main",
            status: .active,
            startedAt: Date().addingTimeInterval(-120),
            lastActivityAt: Date(),
            currentContent: "",
            isTyping: false
        )
    )
}
