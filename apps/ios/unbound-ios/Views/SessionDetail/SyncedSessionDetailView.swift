import MobileClaudeCodeConversationTimeline
import SwiftUI

struct SyncedSessionDetailView: View {
    let session: SyncedSession

    @Environment(\.navigationManager) private var navigationManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: ClaudeSyncedSessionDetailViewModel
    @State private var hasAppliedInitialBottomScroll = false
    @State private var showCreatePRComposer = false
    @State private var deleteBranchOnMerge = false
    @State private var showCommitComposer = false
    @State private var showPushComposer = false
    @State private var commitMessage = ""
    @State private var commitStageAll = true
    @State private var pushRemote = ""
    @State private var pushBranch = ""
    @State private var presenceService = DevicePresenceService.shared

    private let syncedDataService = SyncedDataService.shared

    init(
        session: SyncedSession,
        claudeMessageSource: ClaudeSessionMessageSource = ClaudeRemoteSessionMessageSource()
    ) {
        self.session = session
        _viewModel = State(
            initialValue: ClaudeSyncedSessionDetailViewModel(
                session: session,
                claudeMessageSource: claudeMessageSource
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
        let _ = presenceService.daemonStatusVersion
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

                    if session.deviceId != nil {
                        Menu {
                            Button {
                                showCreatePRComposer = true
                            } label: {
                                Label("Create PR", systemImage: "arrow.triangle.pull")
                            }

                            Button {
                                showCommitComposer = true
                            } label: {
                                Label("Commit", systemImage: "checkmark.circle")
                            }

                            Button {
                                showPushComposer = true
                            } label: {
                                Label("Push", systemImage: "arrow.up.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(!viewModel.canRunPRActions)
                    }

                    Button {
                        Task {
                            await viewModel.loadMessages(force: true)
                            await viewModel.refreshPullRequests()
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
        .alert("Command Complete", isPresented: Binding(
            get: { viewModel.commandNotice != nil },
            set: { if !$0 { viewModel.dismissNotice() } }
        )) {
            Button("OK") { viewModel.dismissNotice() }
        } message: {
            if let notice = viewModel.commandNotice {
                Text(notice)
            }
        }
        .sheet(isPresented: $showCommitComposer) {
            NavigationStack {
                Form {
                    Section("Commit Message") {
                        TextField("Message", text: $commitMessage, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                    }
                    Section {
                        Toggle("Stage all changes", isOn: $commitStageAll)
                    }
                }
                .navigationTitle("Commit Changes")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCommitComposer = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Commit") {
                            let message = commitMessage
                            showCommitComposer = false
                            commitMessage = ""
                            Task {
                                await viewModel.commitChanges(
                                    message: message,
                                    stageAll: commitStageAll
                                )
                            }
                        }
                        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showPushComposer) {
            NavigationStack {
                Form {
                    Section("Remote") {
                        TextField("origin", text: $pushRemote)
                    }
                    Section("Branch") {
                        TextField("main", text: $pushBranch)
                    }
                }
                .navigationTitle("Push Changes")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showPushComposer = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Push") {
                            let remote = pushRemote.trimmingCharacters(in: .whitespacesAndNewlines)
                            let branch = pushBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                            showPushComposer = false
                            pushRemote = ""
                            pushBranch = ""
                            Task {
                                await viewModel.pushChanges(
                                    remote: remote.isEmpty ? nil : remote,
                                    branch: branch.isEmpty ? nil : branch
                                )
                            }
                        }
                    }
                }
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
        VStack(spacing: AppTheme.spacingXS) {
            if viewModel.isDaemonOffline {
                offlineBanner
            }

            planModeToggle

            ChatInputView(text: $viewModel.inputText, placeholder: viewModel.inputPlaceholder) {
                Task { await viewModel.sendMessage() }
            }
            .disabled(!viewModel.canSendMessage)
        }
    }

    private var planModeToggle: some View {
        Button {
            viewModel.isPlanModeEnabled.toggle()
        } label: {
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: viewModel.isPlanModeEnabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(viewModel.isPlanModeEnabled ? AppTheme.accent : AppTheme.textSecondary)
                Text("Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingXS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, AppTheme.spacingM)
        }
        .buttonStyle(.plain)
    }

    private var offlineBanner: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            Image(systemName: "bolt.slash.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daemon offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Remote commands are unavailable. Wait for the device to reconnect.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.spacingM)
        .padding(.vertical, AppTheme.spacingS)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AppTheme.spacingM) {
                    headerCard
                    if let device = syncedDataService.device(for: session) {
                        sessionDeviceCard(device)
                    } else if session.deviceId != nil {
                        devicePlaceholderCard
                    }
                    if session.deviceId != nil {
                        pullRequestPanel
                    }

                    LazyVStack(spacing: AppTheme.spacingS) {
                        ForEach(visibleMessages) { message in
                            ClaudeMessageBubbleView(message: message, showRoleIcon: false)
                        }
                    }

                    if let summary = viewModel.latestCompletionSummary {
                        sessionCompletionFooterCard(summary: summary)
                            .padding(.horizontal, AppTheme.spacingM)
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

    private func sessionCompletionFooterCard(summary: SessionCompletionSummary) -> some View {
        let metrics = sessionCompletionMetrics(for: summary)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: AppTheme.spacingS) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 63 / 255, green: 185 / 255, blue: 80 / 255))

                Text("Session Complete")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(completionPrimaryTextColor)

                Text(summary.outcomeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(completionSecondaryTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(completionTagBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            if let summaryText = summary.summaryText {
                Text(summaryText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(completionSecondaryTextColor)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            if !metrics.isEmpty {
                HStack(spacing: AppTheme.spacingS) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                        Text(metric)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(completionMutedTextColor)

                        if index < metrics.count - 1 {
                            Text("|")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(completionDividerColor)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(completionCardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                .stroke(completionCardBorderColor, lineWidth: 1)
        )
    }

    private func sessionCompletionMetrics(for summary: SessionCompletionSummary) -> [String] {
        var metrics: [String] = []

        if let turns = summary.turns {
            let suffix = turns == 1 ? "" : "s"
            metrics.append("\(turns) turn\(suffix)")
        }

        if let totalTokens = summary.totalTokens {
            metrics.append("\(compactNumber(totalTokens)) tokens")
        }

        if let totalCostUSD = summary.totalCostUSD {
            metrics.append(String(format: "$%.2f", totalCostUSD))
        }

        if let durationMs = summary.durationMs {
            metrics.append(formattedDuration(milliseconds: durationMs))
        }

        return metrics
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            let formatted = Double(value) / 1_000_000
            return String(format: "%.1fm", formatted)
        }

        if value >= 1_000 {
            let formatted = Double(value) / 1_000
            return String(format: "%.1fk", formatted)
        }

        return "\(value)"
    }

    private func formattedDuration(milliseconds: Int) -> String {
        if milliseconds < 1000 {
            return "\(milliseconds)ms"
        }

        let seconds = Double(milliseconds) / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }

        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    private var completionCardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
        }
        return Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    }

    private var completionCardBorderColor: Color {
        if colorScheme == .dark {
            return Color(red: 63 / 255, green: 185 / 255, blue: 80 / 255, opacity: 0.25)
        }
        return Color(red: 63 / 255, green: 185 / 255, blue: 80 / 255, opacity: 0.35)
    }

    private var completionPrimaryTextColor: Color {
        colorScheme == .dark ? Color(red: 229 / 255, green: 229 / 255, blue: 229 / 255) : AppTheme.textPrimary
    }

    private var completionSecondaryTextColor: Color {
        colorScheme == .dark ? Color(red: 163 / 255, green: 163 / 255, blue: 163 / 255) : AppTheme.textSecondary
    }

    private var completionMutedTextColor: Color {
        colorScheme == .dark ? Color(red: 82 / 255, green: 82 / 255, blue: 82 / 255) : AppTheme.textTertiary
    }

    private var completionDividerColor: Color {
        colorScheme == .dark ? Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255) : AppTheme.textTertiary.opacity(0.8)
    }

    private var completionTagBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: runtimeStatusIconName)
                    .font(.caption)

                Text("Runtime: \(viewModel.codingSessionStatus.displayName)")
                    .font(.caption.monospaced())
            }
            .foregroundStyle(runtimeStatusColor)
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, 6)
            .background(runtimeStatusColor.opacity(0.14))
            .clipShape(Capsule())

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

            if let runtimeError = viewModel.codingSessionErrorMessage {
                Label(runtimeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
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

    private func sessionDeviceCard(_ device: SyncedDevice) -> some View {
        let status = syncedDataService.mergedStatus(for: device)
        return Button {
            navigationManager.navigateToSyncedDevice(device)
        } label: {
            HStack(spacing: AppTheme.spacingM) {
                ZStack {
                    Circle()
                        .fill(AppTheme.amberAccent.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: device.deviceType.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.amberAccent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.hostname ?? device.name)
                        .font(Typography.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(status == .online ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(status.displayName)
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)

                        if let lastSeen = device.lastSeenAt {
                            Text("· \(lastSeen.formatted(.relative(presentation: .named)))")
                                .font(Typography.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }

                }

                Spacer()

                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(AppTheme.spacingM)
        }
        .buttonStyle(.plain)
        .thinBorderCard()
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var devicePlaceholderCard: some View {
        HStack(spacing: AppTheme.spacingS) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Device details unavailable")
                    .font(Typography.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Text("Waiting for synced device data.")
                    .font(Typography.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()
        }
        .padding(AppTheme.spacingM)
        .thinBorderCard()
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var runtimeStatusColor: Color {
        switch viewModel.codingSessionStatus {
        case .running:
            return .green
        case .idle:
            return AppTheme.textSecondary
        case .waiting:
            return .orange
        case .notAvailable:
            return AppTheme.textSecondary
        case .error:
            return .red
        }
    }

    private var runtimeStatusIconName: String {
        switch viewModel.codingSessionStatus {
        case .running:
            return "play.circle.fill"
        case .idle:
            return "pause.circle.fill"
        case .waiting:
            return "hourglass.circle.fill"
        case .notAvailable:
            return "slash.circle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var pullRequestPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            HStack {
                Label("Pull Requests", systemImage: "arrow.triangle.pull")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.refreshPullRequests() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoadingPullRequests)
            }

            if showCreatePRComposer {
                VStack(spacing: AppTheme.spacingS) {
                    TextField("PR title", text: $viewModel.prTitle)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $viewModel.prBody)
                        .frame(minHeight: 64, maxHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )

                    HStack {
                        Button("Create PR") {
                            Task { await viewModel.createPullRequest() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.prTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreatingPullRequest)

                        Button("Cancel") {
                            showCreatePRComposer = false
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
            }

            if viewModel.pullRequests.isEmpty {
                Text(viewModel.isLoadingPullRequests ? "Loading PRs..." : "No pull requests")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    ForEach(viewModel.pullRequests.prefix(5), id: \.number) { pullRequest in
                        Button {
                            Task { await viewModel.selectPullRequest(pullRequest) }
                        } label: {
                            HStack(spacing: AppTheme.spacingXS) {
                                Text("#\(pullRequest.number)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(pullRequest.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Text(pullRequest.state)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selected = viewModel.selectedPullRequest {
                Divider()
                HStack {
                    Text("Selected: #\(selected.number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Picker("Merge", selection: $viewModel.prMergeMethod) {
                        Text("Merge").tag("merge")
                        Text("Squash").tag("squash")
                        Text("Rebase").tag("rebase")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                if let checks = viewModel.selectedPullRequestChecks {
                    Text("Checks: \(checks.summary.passing) pass, \(checks.summary.failing) fail, \(checks.summary.pending) pending")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Toggle("Delete branch", isOn: $deleteBranchOnMerge)
                    .font(.caption)

                Button("Merge Selected PR") {
                    Task { await viewModel.mergeSelectedPullRequest(deleteBranch: deleteBranchOnMerge) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isMergingPullRequest || !viewModel.canRunPRActions)
            }
        }
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
                    claudeMessageSource: ClaudeFixtureSessionMessageSource(loader: fixture.loader)
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
