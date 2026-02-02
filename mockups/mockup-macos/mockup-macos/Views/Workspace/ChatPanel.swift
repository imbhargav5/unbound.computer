//
//  ChatPanel.swift
//  mockup-macos
//
//  Shadcn-styled chat panel with mock data.
//

import SwiftUI

struct ChatPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MockAppState.self) private var appState

    let session: Session?
    let repository: Repository?
    @Binding var chatInput: String
    @Binding var selectedModel: AIModel
    @Binding var selectedThinkMode: ThinkMode
    @Binding var isPlanMode: Bool

    // Mock streaming state
    @State private var isStreaming: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Mock messages - using messages with sub-agents to demonstrate sub-agent UI
    private var messages: [ChatMessage] {
        FakeData.messagesWithSubAgents
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with project name
            ChatHeader(projectName: repository?.name ?? "No Repository")

            ShadcnDivider()

            // Chat content
            VStack(spacing: 0) {
                if let session = session {
                    if messages.isEmpty {
                        // Welcome view for empty chat
                        WelcomeChatView(
                            repoPath: repository?.name ?? "repository",
                            tip: FakeData.tipMessage
                        )
                        Spacer()
                    } else {
                        // Messages list
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                        ChatMessageView(
                                            message: message,
                                            index: index
                                        )
                                        .id(message.id)
                                    }

                                    // Invisible scroll anchor at bottom
                                    Color.clear.frame(height: 1).id("bottomAnchor")
                                }
                            }
                        }
                    }

                    // Input field at bottom
                    ChatInputField(
                        text: $chatInput,
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: $isPlanMode,
                        isStreaming: isStreaming,
                        onSend: sendMessage,
                        onCancel: cancelStream
                    )
                    .padding(Spacing.compact)
                } else {
                    // No session selected
                    ContentUnavailableView(
                        "No Chat Selected",
                        systemImage: "message",
                        description: Text("Select a session or create a new one")
                    )
                }
            }
            .background(colors.background)

            ShadcnDivider()

            // Footer (empty, 20px height)
            Color.clear
                .frame(height: 20)
                .background(colors.card)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // For mockup, just clear input
        chatInput = ""

        // Simulate streaming
        isStreaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isStreaming = false
        }
    }

    private func cancelStream() {
        isStreaming = false
    }
}

#Preview {
    ChatPanel(
        session: FakeData.sessions.first,
        repository: FakeData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false)
    )
    .environment(MockAppState())
    .frame(width: 550, height: 600)
}
