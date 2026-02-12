//
//  SessionDetailView.swift
//  unbound-macos
//
//  Fixture-oriented session detail timeline for Canvas preview validation.
//

import SwiftUI

struct SessionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: Session
    let messages: [ChatMessage]
    let sourceMessageCount: Int

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(sessionTitle: session.displayTitle)
            ShadcnDivider()

            if messages.isEmpty {
                emptyState
            } else {
                contentView
            }
        }
        .background(colors.chatBackground)
    }

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headerCard

                    LazyVStack(spacing: 0) {
                        ForEach(messages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                }
                .padding(.vertical, Spacing.lg)
            }
            .onAppear {
                if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("Session Detail")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

                Badge(session.status.rawValue.capitalized, variant: statusBadgeVariant)

                Spacer()
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Session ID")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text(session.id.uuidString.lowercased())
                    .font(Typography.mono)
                    .foregroundStyle(colors.foreground)
                    .textSelection(.enabled)
            }

            HStack(spacing: Spacing.lg) {
                statPill(title: "Rendered", value: "\(messages.count)")
                statPill(title: "Source Rows", value: "\(sourceMessageCount)")
            }

            HStack(spacing: Spacing.sm) {
                Text("Created")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                Text(session.createdAt, style: .date)
                    .font(Typography.caption)
                    .foregroundStyle(colors.foreground)

                Text("•")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text("Last Accessed")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                Text(session.lastAccessed, style: .relative)
                    .font(Typography.caption)
                    .foregroundStyle(colors.foreground)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
        .padding(.horizontal, Spacing.lg)
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typography.micro)
                .foregroundStyle(colors.mutedForeground)

            Text(value)
                .font(Typography.label)
                .foregroundStyle(colors.foreground)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var statusBadgeVariant: Badge.BadgeVariant {
        switch session.status {
        case .active:
            return .default
        case .archived:
            return .secondary
        case .error:
            return .destructive
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Renderable Messages",
            systemImage: "text.bubble",
            description: Text("Fixture loaded, but no assistant/user timeline messages were parsed.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
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

#Preview("Session Detail - Status Variants") {
    SessionDetailStatusVariantsPreview()
        .frame(width: 960, height: 700)
}
#endif
