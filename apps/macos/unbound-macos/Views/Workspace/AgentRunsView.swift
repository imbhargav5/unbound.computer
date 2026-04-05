//
//  AgentRunsView.swift
//  unbound-macos
//
//  Cross-project run history for a persisted agent_id.
//

import SwiftUI

struct AgentRunsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let currentSession: Session
    let runs: [Session]
    let repositoriesById: [UUID: Repository]
    let onSelectRun: (Session) -> Void

    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if runs.isEmpty {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("This agent has no saved runs yet.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(runs) { run in
                            runRow(run)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.chatBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(currentSession.displayAgentName) Runs")
                .font(Typography.h3)
                .foregroundStyle(colors.foreground)

            Text("\(runs.count) saved \(runs.count == 1 ? "run" : "runs") across repositories")
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    private func runRow(_ run: Session) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Button {
                onSelectRun(run)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(run.displayTitle)
                                .font(Typography.bodyMedium)
                                .foregroundStyle(colors.foreground)
                                .lineLimit(1)

                            Text(repositoriesById[run.repositoryId]?.name ?? "Unknown repository")
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: Spacing.xs) {
                            if run.isWorktree {
                                Badge("Worktree", variant: .outline)
                            }
                            if run.id == currentSession.id {
                                Badge("Current", variant: .secondary)
                            }
                        }
                    }

                    if let issueTitle = run.displayIssueTitle {
                        HStack(spacing: Spacing.xs) {
                            Text("Issue")
                                .font(Typography.micro)
                                .foregroundStyle(colors.mutedForeground)

                            Text(issueTitle)
                                .font(Typography.caption)
                                .foregroundStyle(colors.foreground)
                                .lineLimit(1)

                            if let issueId = run.issueId,
                               run.issueTitle != nil,
                               issueId != issueTitle {
                                Text(issueId)
                                    .font(Typography.micro)
                                    .foregroundStyle(colors.mutedForeground)
                                    .lineLimit(1)
                            }
                        }
                    }

                    HStack(spacing: Spacing.sm) {
                        Text(statusLabel(for: run.status))
                            .font(Typography.micro)
                            .foregroundStyle(statusColor(for: run.status))

                        Text("Created \(Self.timestampFormatter.localizedString(for: run.createdAt, relativeTo: Date()))")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)

                        Text("Opened \(Self.timestampFormatter.localizedString(for: run.lastAccessed, relativeTo: Date()))")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }

                    Text("Last opened \(Self.absoluteFormatter.string(from: run.lastAccessed))")
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground.opacity(0.9))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let issueURL = issueURL(for: run) {
                Button {
                    openURL(issueURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: IconSize.sm, weight: .medium))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: 28, height: 28)
                        .background(colors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .iconTooltip(IconTooltipSpec("Open issue"))
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(for: run))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(run.id == currentSession.id ? colors.selectionBorder : colors.border, lineWidth: BorderWidth.default)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func rowBackground(for run: Session) -> some ShapeStyle {
        run.id == currentSession.id ? colors.selectionBackground : colors.card
    }

    private func statusLabel(for status: SessionStatus) -> String {
        switch status {
        case .active:
            return "Active"
        case .archived:
            return "Archived"
        case .error:
            return "Error"
        }
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .active:
            return colors.success
        case .archived:
            return colors.mutedForeground
        case .error:
            return colors.destructive
        }
    }

    private func issueURL(for run: Session) -> URL? {
        guard let raw = run.issueURL else { return nil }
        return URL(string: raw)
    }
}

#if DEBUG

#Preview("Agent Runs") {
    let currentSession = Session(
        id: PreviewData.sessionId1,
        repositoryId: PreviewData.repoId1,
        title: "Implement WebSocket relay",
        agentId: "agent-preview",
        agentName: "Ops Agent",
        issueId: "ENG-123",
        issueTitle: "Investigate relay connection drift",
        issueURL: "https://example.com/issues/ENG-123",
        status: .active,
        createdAt: Date().addingTimeInterval(-7200),
        lastAccessed: Date()
    )
    let historicalRun = Session(
        id: PreviewData.sessionId4,
        repositoryId: PreviewData.repoId2,
        title: "Add rebase support",
        agentId: "agent-preview",
        agentName: "Ops Agent",
        issueId: "ENG-101",
        issueTitle: "Stabilize rebase workflow",
        issueURL: "https://example.com/issues/ENG-101",
        status: .archived,
        createdAt: Date().addingTimeInterval(-172800),
        lastAccessed: Date().addingTimeInterval(-86400)
    )

    return AgentRunsView(
        currentSession: currentSession,
        runs: [currentSession, historicalRun],
        repositoriesById: Dictionary(uniqueKeysWithValues: PreviewData.repositories.map { ($0.id, $0) }),
        onSelectRun: { _ in }
    )
    .preferredColorScheme(.dark)
    .frame(width: 920, height: 620)
}

#endif
