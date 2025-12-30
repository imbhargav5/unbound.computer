//
//  AskUserQuestionView.swift
//  rocketry-macos
//
//  Display interactive questions with selectable options
//

import SwiftUI

struct AskUserQuestionView: View {
    @Environment(\.colorScheme) private var colorScheme

    let question: AskUserQuestion
    var onSubmit: (AskUserQuestion) -> Void

    @State private var selectedOptions: Set<String> = []
    @State private var textInput: String = ""

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header badge
            if let header = question.header {
                Text(header)
                    .font(Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.primary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(colors.primary.opacity(0.1))
                    )
            }

            // Question text
            Text(question.question)
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            // Options
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(question.options) { option in
                    OptionButton(
                        option: option,
                        isSelected: selectedOptions.contains(option.id),
                        allowsMultiSelect: question.allowsMultiSelect,
                        onSelect: {
                            toggleOption(option)
                        }
                    )
                }
            }

            // Text input (if allowed)
            if question.allowsTextInput {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Or type your response:")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)

                    TextField("Your response...", text: $textInput)
                        .textFieldStyle(.plain)
                        .font(Typography.body)
                        .padding(Spacing.sm)
                        .background(colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(colors.border, lineWidth: BorderWidth.default)
                        )
                }
            }

            // Submit button
            HStack {
                Spacer()

                Button {
                    submit()
                } label: {
                    Text("Submit")
                        .font(Typography.bodySmall)
                }
                .buttonPrimary(size: .sm)
                .disabled(!canSubmit)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.primary.opacity(0.3), lineWidth: BorderWidth.default)
        )
    }

    private var canSubmit: Bool {
        !selectedOptions.isEmpty || !textInput.isEmpty
    }

    private func toggleOption(_ option: QuestionOption) {
        if question.allowsMultiSelect {
            if selectedOptions.contains(option.id) {
                selectedOptions.remove(option.id)
            } else {
                selectedOptions.insert(option.id)
            }
        } else {
            selectedOptions = [option.id]
        }
    }

    private func submit() {
        var updatedQuestion = question
        updatedQuestion.selectedOptions = selectedOptions
        updatedQuestion.textResponse = textInput.isEmpty ? nil : textInput
        onSubmit(updatedQuestion)
    }
}

// MARK: - Option Button

struct OptionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let option: QuestionOption
    let isSelected: Bool
    let allowsMultiSelect: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Selection indicator
                ZStack {
                    if allowsMultiSelect {
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .stroke(isSelected ? colors.primary : colors.border, lineWidth: BorderWidth.default)
                            .frame(width: 18, height: 18)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(colors.primary)
                        }
                    } else {
                        Circle()
                            .stroke(isSelected ? colors.primary : colors.border, lineWidth: BorderWidth.default)
                            .frame(width: 18, height: 18)

                        if isSelected {
                            Circle()
                                .fill(colors.primary)
                                .frame(width: 10, height: 10)
                        }
                    }
                }

                // Option content
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(option.label)
                        .font(Typography.body)
                        .foregroundStyle(colors.foreground)

                    if let description = option.description {
                        Text(description)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                }

                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(isSelected ? colors.primary : colors.border, lineWidth: BorderWidth.default)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    AskUserQuestionView(
        question: AskUserQuestion(
            question: "Which library should we use for date formatting?",
            header: "Library",
            options: [
                QuestionOption(label: "Swift Foundation (Recommended)", description: "Built-in, no dependencies"),
                QuestionOption(label: "SwiftDate", description: "Rich API, more features"),
                QuestionOption(label: "Chronos", description: "Lightweight alternative")
            ],
            allowsMultiSelect: false,
            allowsTextInput: true
        ),
        onSubmit: { _ in }
    )
    .frame(width: 450)
    .padding()
}
