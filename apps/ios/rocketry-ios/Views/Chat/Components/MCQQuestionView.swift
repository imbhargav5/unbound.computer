import SwiftUI

struct MCQQuestionView: View {
    let question: MCQQuestion
    let onOptionSelected: (MCQQuestion.MCQOption) -> Void
    let onCustomInputRequested: () -> Void

    @State private var selectedId: UUID?

    /// All options including "Something else"
    private var allOptions: [MCQQuestion.MCQOption] {
        question.options + [MCQQuestion.somethingElseOption]
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            ClaudeAvatarView(size: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                // Question text
                Text(question.question)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(AppTheme.spacingM)
                    .background(AppTheme.assistantBubble)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))

                // Options (including "Something else")
                VStack(spacing: AppTheme.spacingS) {
                    ForEach(allOptions) { option in
                        MCQOptionCardView(
                            option: option,
                            isSelected: selectedId == option.id,
                            isConfirmed: question.isConfirmed,
                            isDisabled: question.isConfirmed && selectedId != option.id
                        ) {
                            handleSelection(option)
                        }
                    }
                }

                // Show custom answer if confirmed with custom text
                if question.isConfirmed, let customAnswer = question.customAnswer, !customAnswer.isEmpty {
                    HStack(spacing: AppTheme.spacingS) {
                        Image(systemName: "text.bubble.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                        Text(customAnswer)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .padding(AppTheme.spacingM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.toolBadgeBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, AppTheme.spacingM)
        .onAppear {
            if let existingSelection = question.selectedOptionId {
                selectedId = existingSelection
            } else if question.hasCustomAnswer {
                // If there's a custom answer, select the "Something else" option
                selectedId = MCQQuestion.somethingElseOption.id
            }
        }
    }

    private func handleSelection(_ option: MCQQuestion.MCQOption) {
        guard !question.isConfirmed else { return }

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedId = option.id
        }

        if option.isCustomOption {
            // "Something else" tapped - request custom input
            onCustomInputRequested()
        } else {
            // Regular option selected
            onOptionSelected(option)
        }
    }
}

// MARK: - Option Card

struct MCQOptionCardView: View {
    let option: MCQQuestion.MCQOption
    let isSelected: Bool
    let isConfirmed: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    private var showCheckmark: Bool {
        isSelected && isConfirmed
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.spacingM) {
                // Option icon
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isSelected ? (isConfirmed ? .white : AppTheme.accent) : AppTheme.accent)
                        .frame(width: 24)
                }

                // Label and description
                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    Text(option.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected && isConfirmed ? .white : AppTheme.textPrimary)

                    if let description = option.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(isSelected && isConfirmed ? .white.opacity(0.8) : AppTheme.textSecondary)
                    }
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppTheme.accent : AppTheme.textTertiary, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(showCheckmark ? .white : AppTheme.accent)
                            .frame(width: showCheckmark ? 22 : 12, height: showCheckmark ? 22 : 12)

                        if showCheckmark {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
            .padding(AppTheme.spacingM)
            .background(AppTheme.cardBackground)
            .background(isSelected && isConfirmed ? AppTheme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(isSelected ? AppTheme.accent : AppTheme.cardBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Previews

#Preview("MCQ Question - No Selection") {
    VStack {
        MCQQuestionView(
            question: MCQQuestion(
                question: "How would you like me to implement this feature?",
                options: [
                    MCQQuestion.MCQOption(
                        label: "Add to existing file",
                        description: "Modify ChatView.swift with new components",
                        icon: "doc.badge.plus"
                    ),
                    MCQQuestion.MCQOption(
                        label: "Create new files",
                        description: "Create separate component files",
                        icon: "folder.badge.plus"
                    ),
                    MCQQuestion.MCQOption(
                        label: "Let Claude decide",
                        description: "I'll analyze the codebase and choose",
                        icon: "brain.head.profile"
                    )
                ]
            ),
            onOptionSelected: { option in
                print("Selected: \(option.label)")
            },
            onCustomInputRequested: {
                print("Custom input requested")
            }
        )
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}

#Preview("MCQ Question - Confirmed with Custom Answer") {
    VStack {
        MCQQuestionView(
            question: MCQQuestion(
                question: "Which approach do you prefer?",
                options: [
                    MCQQuestion.MCQOption(label: "Option A", description: "First option", icon: "1.circle"),
                    MCQQuestion.MCQOption(label: "Option B", description: "Second option", icon: "2.circle")
                ],
                selectedOptionId: MCQQuestion.somethingElseOption.id,
                customAnswer: "I'd like to use a combination of both approaches",
                isConfirmed: true
            ),
            onOptionSelected: { _ in },
            onCustomInputRequested: { }
        )
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}
