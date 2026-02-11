import SwiftUI

struct SyncedSessionDetailView: View {
    let session: SyncedSession

    @State private var viewModel: SyncedSessionDetailViewModel
    @State private var hasAppliedInitialBottomScroll = false

    init(
        session: SyncedSession,
        messageService: SessionDetailMessageLoading = SessionDetailMessageService()
    ) {
        self.session = session
        _viewModel = State(
            initialValue: SyncedSessionDetailViewModel(
                session: session,
                messageService: messageService
            )
        )
    }

    private var visibleMessages: [Message] {
        viewModel.messages.filter { message in
            guard let blocks = message.parsedContent else {
                // No parsed content - show if content is non-empty
                return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            // Filter out messages where all blocks are empty/whitespace
            return blocks.contains(where: \.isVisibleContent)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isLoading && viewModel.messages.isEmpty {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage, viewModel.messages.isEmpty {
                    errorView(errorMessage: errorMessage)
                } else if viewModel.messages.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }
            .frame(maxHeight: .infinity)

            if session.deviceId != nil {
                sessionInputBar
            }
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppTheme.spacingS) {
                    if viewModel.canStopClaude {
                        Button {
                            Task { await viewModel.stopClaude() }
                        } label: {
                            Image(systemName: "stop.circle")
                                .foregroundStyle(.red)
                        }
                        .disabled(viewModel.isStopping)
                    }

                    Button {
                        Task {
                            await viewModel.loadMessages(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .alert("Command Failed", isPresented: Binding(
            get: { viewModel.commandError != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            if let error = viewModel.commandError {
                Text(error)
            }
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stopRealtimeUpdates()
        }
    }

    private var sessionInputBar: some View {
        ChatInputView(text: $viewModel.inputText) {
            Task { await viewModel.sendMessage() }
        }
    }

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AppTheme.spacingM) {
                    headerCard

                    LazyVStack(spacing: AppTheme.spacingS) {
                        ForEach(visibleMessages) { message in
                            MessageBubbleView(message: message, showRoleIcon: false)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.top, AppTheme.spacingM)
                .padding(.bottom, AppTheme.spacingXL)
            }
            .defaultScrollAnchor(.bottom)
            .refreshable {
                await viewModel.loadMessages(force: true)
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                if oldCount == 0, newCount > 0 {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onAppear {
                guard !hasAppliedInitialBottomScroll, !viewModel.messages.isEmpty else {
                    return
                }
                hasAppliedInitialBottomScroll = true
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        Task { @MainActor in
            proxy.scrollTo("bottom", anchor: .bottom)
            hasAppliedInitialBottomScroll = true
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text("Session ID")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Text(session.id.uuidString)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: AppTheme.spacingM) {
                Label("\(viewModel.messages.count) messages", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                if viewModel.decryptedMessageCount > 0 {
                    Label("\(viewModel.decryptedMessageCount) decrypted", systemImage: "lock.open")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var loadingView: some View {
        VStack(spacing: AppTheme.spacingM) {
            ProgressView()
            Text("Loading and decrypting session messages...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(errorMessage: String) -> some View {
        VStack(spacing: AppTheme.spacingM) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)

            Text("Failed to load session")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingXL)

            Button("Retry") {
                Task {
                    await viewModel.loadMessages(force: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: AppTheme.spacingM) {
            EmptyStateView(
                icon: "text.bubble",
                title: "No Messages",
                message: "This session has no messages yet."
            )

            #if DEBUG
            debugEmptyStateDetails
            #endif
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    #if DEBUG
    private var debugEmptyStateDetails: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Label("Debug Diagnostics", systemImage: "ladybug")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("session_id: \(session.id.uuidString.lowercased())")
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.textSecondary)

            Text("messages_loaded: \(viewModel.messages.count)")
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.textSecondary)

            Text("decrypted_count: \(viewModel.decryptedMessageCount)")
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
    #endif
}

#if DEBUG
private struct SyncedSessionDetailPreviewFixture {
    let session: SyncedSession
    let loader: SessionDetailFixtureMessageLoader

    static func load() throws -> SyncedSessionDetailPreviewFixture {
        let loader = try SessionDetailFixtureMessageLoader()
        let fixture = try loader.loadFixture()

        let sessionID = UUID(uuidString: fixture.session.id) ?? UUID()
        let repositoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let sessionRecord = SessionRecord(
            id: sessionID.uuidString,
            repositoryId: repositoryID.uuidString,
            title: fixture.session.title,
            claudeSessionId: nil,
            isWorktree: false,
            worktreePath: nil,
            status: fixture.session.status,
            deviceId: nil,
            createdAt: fixture.session.createdAt,
            lastAccessedAt: fixture.session.lastAccessedAt,
            updatedAt: fixture.session.lastAccessedAt
        )

        return SyncedSessionDetailPreviewFixture(
            session: SyncedSession(from: sessionRecord),
            loader: loader
        )
    }
}

#Preview("Session Detail Fixture") {
    Group {
        if let fixture = try? SyncedSessionDetailPreviewFixture.load() {
            NavigationStack {
                SyncedSessionDetailView(
                    session: fixture.session,
                    messageService: fixture.loader
                )
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Missing Session Detail Fixture")
                    .font(.headline)
                Text("Run apps/ios/scripts/export_max_session_fixture.sh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    .background(AppTheme.backgroundPrimary)
}
#endif
