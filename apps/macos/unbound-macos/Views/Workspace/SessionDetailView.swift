//
//  SessionDetailView.swift
//  unbound-macos
//
//  Fixture-oriented session detail timeline for Canvas preview validation.
//

import SwiftUI

#if DEBUG

struct SessionDetailView: View {
    let session: Session
    let messages: [ChatMessage]
    let sourceMessageCount: Int

    @State private var chatInput = ""
    @State private var selectedModel: AIModel = .opus
    @State private var selectedThinkMode: ThinkMode = .none
    @State private var isPlanMode = false

    private let repository: Repository
    private let previewAppState: AppState
    private let previewEditorState: EditorState

    init(session: Session, messages: [ChatMessage], sourceMessageCount: Int) {
        self.session = session
        self.messages = messages
        self.sourceMessageCount = sourceMessageCount

        let context = SessionDetailPreviewContext.make(session: session, messages: messages)
        self.repository = context.repository
        self.previewAppState = context.appState
        self.previewEditorState = context.editorState
    }

    var body: some View {
        ChatPanel(
            session: session,
            repository: repository,
            chatInput: $chatInput,
            selectedModel: $selectedModel,
            selectedThinkMode: $selectedThinkMode,
            isPlanMode: $isPlanMode,
            editorState: previewEditorState
        )
        .environment(previewAppState)
        .overlay(alignment: .topLeading) {
            Text("Preview: ChatPanel • rendered \(messages.count) / source \(sourceMessageCount)")
                .font(Typography.micro)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Radius.sm))
                .padding(Spacing.sm)
        }
    }
}

private struct SessionDetailPreviewContext {
    let repository: Repository
    let appState: AppState
    let editorState: EditorState

    static func make(session: Session, messages: [ChatMessage]) -> SessionDetailPreviewContext {
        let repository = resolveRepository(for: session)

        let appState = AppState()
        appState.configureForPreview(
            repositories: [repository],
            sessions: [repository.id: [session]],
            selectedRepositoryId: repository.id,
            selectedSessionId: session.id
        )

        let liveState = SessionLiveState(sessionId: session.id)
        liveState.configureForPreview(messages: messages)
        appState.sessionStateManager.registerForPreview(sessionId: session.id, state: liveState)

        let editorState = EditorState.preview()
        return SessionDetailPreviewContext(
            repository: repository,
            appState: appState,
            editorState: editorState
        )
    }

    private static func resolveRepository(for session: Session) -> Repository {
        if let existing = PreviewData.repositories.first(where: { $0.id == session.repositoryId }) {
            return existing
        }

        if let fallback = PreviewData.repositories.first {
            return Repository(
                id: session.repositoryId,
                path: fallback.path,
                name: fallback.name,
                lastAccessed: session.lastAccessed,
                addedAt: fallback.addedAt,
                isGitRepository: fallback.isGitRepository,
                sessionsPath: fallback.sessionsPath,
                defaultBranch: fallback.defaultBranch,
                defaultRemote: fallback.defaultRemote
            )
        }

        return Repository(
            id: session.repositoryId,
            path: FileManager.default.homeDirectoryForCurrentUser.path,
            name: "Preview Repository",
            lastAccessed: session.lastAccessed,
            addedAt: session.createdAt,
            isGitRepository: true
        )
    }
}

private struct SessionDetailScenarioPreview: View {
    let scenario: SessionDetailPreviewScenario

    @State private var previewData: SessionDetailPreviewData?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let previewData {
                SessionDetailView(
                    session: previewData.session,
                    messages: previewData.parsedMessages,
                    sourceMessageCount: previewData.sourceMessageCount
                )
            } else if let loadError {
                SessionDetailFixtureErrorView(errorMessage: loadError)
            } else {
                VStack(spacing: Spacing.md) {
                    ProgressView()

                    Text(scenario.loadingTitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadPreviewDataIfNeeded()
        }
    }

    private func loadPreviewDataIfNeeded() async {
        guard previewData == nil && loadError == nil else { return }

        do {
            previewData = try SessionDetailPreviewScenarioBuilder.load(scenario)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct SessionDetailStatusVariantsPreview: View {
    private enum StatusVariant: String, CaseIterable, Identifiable {
        case archived
        case error

        var id: String { rawValue }

        var label: String {
            switch self {
            case .archived:
                return "Archived"
            case .error:
                return "Error"
            }
        }
    }

    @State private var variants: SessionDetailStatusVariants?
    @State private var selectedStatus: StatusVariant = .archived
    @State private var loadError: String?

    var body: some View {
        Group {
            if let variants {
                let selectedData = selectedData(from: variants)
                VStack(spacing: 0) {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(StatusVariant.allCases) { variant in
                            Text(variant.label)
                                .tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)

                    SessionDetailView(
                        session: selectedData.session,
                        messages: selectedData.parsedMessages,
                        sourceMessageCount: selectedData.sourceMessageCount
                    )
                }
            } else if let loadError {
                SessionDetailFixtureErrorView(errorMessage: loadError)
            } else {
                VStack(spacing: Spacing.md) {
                    ProgressView()

                    Text("Loading Status Variants...")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadStatusVariantsIfNeeded()
        }
    }

    private func selectedData(from variants: SessionDetailStatusVariants) -> SessionDetailPreviewData {
        switch selectedStatus {
        case .archived:
            return variants.archived
        case .error:
            return variants.error
        }
    }

    private func loadStatusVariantsIfNeeded() async {
        guard variants == nil && loadError == nil else { return }

        do {
            variants = try SessionDetailPreviewScenarioBuilder.loadStatusVariants()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct SessionDetailFixtureErrorView: View {
    let errorMessage: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IconSize.xxl))
                .foregroundStyle(.orange)

            Text("Missing Session Detail Fixture")
                .font(Typography.h4)

            Text(errorMessage)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Text("Run:\napps/ios/scripts/export_max_session_fixture.sh \"<db-path>\" \"apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json\"")
                .font(Typography.code)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(Spacing.xl)
    }
}

#Preview("Session Detail - Fixture Max") {
    SessionDetailScenarioPreview(scenario: .fixtureMax)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Fixture Max (Light)") {
    SessionDetailScenarioPreview(scenario: .fixtureMax)
        .preferredColorScheme(.light)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Fixture Max (Dark)") {
    SessionDetailScenarioPreview(scenario: .fixtureMax)
        .preferredColorScheme(.dark)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Fixture Short") {
    SessionDetailScenarioPreview(scenario: .fixtureShort)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Empty Timeline") {
    SessionDetailScenarioPreview(scenario: .emptyTimeline)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Text Heavy") {
    SessionDetailScenarioPreview(scenario: .textHeavySynthetic)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Tool Heavy") {
    SessionDetailScenarioPreview(scenario: .toolHeavySynthetic)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Table Spec") {
    SessionDetailScenarioPreview(scenario: .tableSpecSynthetic)
        .frame(width: 960, height: 700)
}

#Preview("Session Detail - Status Variants") {
    SessionDetailStatusVariantsPreview()
        .frame(width: 960, height: 700)
}
#endif
