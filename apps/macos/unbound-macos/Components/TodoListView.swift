//
//  TodoListView.swift
//  unbound-macos
//
//  Display todo lists with status indicators
//

import SwiftUI

struct TodoListView: View {
    @Environment(\.colorScheme) private var colorScheme

    let todoList: TodoList

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(todoList.items) { item in
                TodoItemRow(item: item)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Todo Item Row

struct TodoItemRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: TodoItem

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status indicator
            statusIcon

            // Content
            Text(item.content)
                .font(Typography.body)
                .foregroundStyle(item.status == .completed ? colors.mutedForeground : colors.foreground)
                .strikethrough(item.status == .completed, color: colors.mutedForeground)

            Spacer()

            // Status badge
            if item.status == .inProgress {
                Text("In Progress")
                    .font(Typography.caption)
                    .foregroundStyle(colors.warning)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(colors.warning.opacity(0.1))
                    )
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Circle()
                .stroke(colors.border, lineWidth: BorderWidth.default)
                .frame(width: 18, height: 18)

        case .inProgress:
            // Animated spinner
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 18, height: 18)

        case .completed:
            ZStack {
                Circle()
                    .fill(colors.success)
                    .frame(width: 18, height: 18)

                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

#if DEBUG

#Preview {
    TodoListView(todoList: TodoList(items: [
        TodoItem(content: "Research existing metrics tracking in the codebase", status: .completed),
        TodoItem(content: "Design the metrics collection system", status: .completed),
        TodoItem(content: "Implement core metrics tracking functionality", status: .inProgress),
        TodoItem(content: "Create export functionality for different formats", status: .pending),
        TodoItem(content: "Add unit tests", status: .pending)
    ]))
    .frame(width: 500)
    .padding()
}

#endif
