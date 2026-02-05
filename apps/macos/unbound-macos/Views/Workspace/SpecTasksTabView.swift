//
//  SpecTasksTabView.swift
//  unbound-macos
//
//  Spec and Tasks panel for the right sidebar.
//  Shows implementation plan and task progress.
//  Currently uses hardcoded demo data.
//

import SwiftUI

// MARK: - Spec Tasks Tab

enum SpecTasksSection: String, CaseIterable, Identifiable {
    case spec = "Spec"
    case tasks = "Tasks"

    var id: String { rawValue }
}

struct SpecTasksTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSection: SpecTasksSection = .tasks

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // Hardcoded demo tasks
    private let demoTasks: [DemoTask] = [
        DemoTask(title: "Create AgentCardView component", status: .completed),
        DemoTask(title: "Add amber accent color theme", status: .completed),
        DemoTask(title: "Update SemanticColors with new palette", status: .completed),
        DemoTask(title: "Create SpecTasksTabView panel", status: .inProgress),
        DemoTask(title: "Integrate agent cards in ChatPanel", status: .pending),
        DemoTask(title: "Add connector lines to tool rows", status: .pending),
        DemoTask(title: "Test and verify styling matches design", status: .pending)
    ]

    private var completedCount: Int {
        demoTasks.filter { $0.status == .completed }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section tabs + Approve
            sectionTabs

            ShadcnDivider()

            // Content
            switch selectedSection {
            case .spec:
                specContent
            case .tasks:
                tasksContent
            }
        }
    }

    // MARK: - Section Tabs

    private var sectionTabs: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(SpecTasksSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(Typography.toolbar)
                        .fontWeight(selectedSection == section ? .semibold : .regular)
                        .foregroundStyle(selectedSection == section ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .overlay(alignment: .bottom) {
                            if selectedSection == section {
                                Rectangle()
                                    .fill(colors.accentAmber)
                                    .frame(height: 2)
                                    .offset(y: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: {}) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.xs))
                    Text("Approve")
                        .font(Typography.toolbar)
                }
                .foregroundStyle(colors.primaryActionForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colors.primaryAction)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
    }

    // MARK: - Spec Content

    private var specContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Implementation Plan header
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(colors.accentAmberMuted)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
                                .foregroundStyle(colors.accentAmber)
                        )

                    Text("Implementation Plan")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                }

                // Spec description
                Text("Update the unbound-macos application to match the Claude Code design specification with amber accent colors and new agent card UI components.")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                ShadcnDivider()

                // Key objectives
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Key Objectives")
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.sidebarText)

                    specBullet("Implement amber (#F59E0B) as primary accent color")
                    specBullet("Create AgentCardView with nested tool display")
                    specBullet("Add Spec/Tasks panel to right sidebar")
                    specBullet("Update existing components to use new theme")
                }
            }
            .padding(Spacing.md)
        }
    }

    private func specBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(colors.accentAmber)
                .frame(width: 4, height: 4)
                .padding(.top, 6)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
        }
    }

    // MARK: - Tasks Content

    private var tasksContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Progress header
                HStack(spacing: Spacing.sm) {
                    Text("\(completedCount)/\(demoTasks.count) completed")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)

                    Spacer()

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(colors.surface2)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(colors.accentAmber)
                                .frame(width: geo.size.width * (Double(completedCount) / Double(demoTasks.count)), height: 4)
                        }
                    }
                    .frame(width: 80, height: 4)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)

                ShadcnDivider()

                // Task list
                ForEach(demoTasks) { task in
                    TaskRow(task: task)
                }
            }
        }
    }
}

// MARK: - Demo Task Model

struct DemoTask: Identifiable {
    let id = UUID()
    let title: String
    let status: DemoTaskStatus
}

enum DemoTaskStatus {
    case pending
    case inProgress
    case completed
}

// MARK: - Task Row

struct TaskRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let task: DemoTask

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Status indicator
            statusIcon

            // Task title
            Text(task.title)
                .font(Typography.caption)
                .foregroundStyle(task.status == .completed ? colors.mutedForeground : colors.foreground)
                .strikethrough(task.status == .completed, color: colors.mutedForeground)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Circle()
                .stroke(colors.border, lineWidth: 1.5)
                .frame(width: 14, height: 14)

        case .inProgress:
            Circle()
                .fill(colors.accentAmberMuted)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .fill(colors.accentAmber)
                        .frame(width: 6, height: 6)
                )

        case .completed:
            Circle()
                .fill(colors.success)
                .frame(width: 14, height: 14)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(colors.background)
                )
        }
    }
}

// MARK: - Preview

#Preview {
    SpecTasksTabView()
        .frame(width: 280, height: 500)
        .background(Color(hex: "0D0D0D"))
}
