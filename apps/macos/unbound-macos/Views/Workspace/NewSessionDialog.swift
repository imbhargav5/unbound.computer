//
//  NewSessionDialog.swift
//  unbound-macos
//
//  Dialog for choosing where to create a new session:
//  - Main Directory: Work directly in the repository
//  - New Worktree: Create an isolated git worktree
//

import SwiftUI

// MARK: - Session Location Type

enum SessionLocationType: String, CaseIterable {
    case mainDirectory
    case worktree

    var title: String {
        switch self {
        case .mainDirectory: return "Main Directory"
        case .worktree: return "New Worktree"
        }
    }

    var description: String {
        switch self {
        case .mainDirectory: return "Work directly in the repo"
        case .worktree: return "Isolated git worktree"
        }
    }

    var icon: String {
        switch self {
        case .mainDirectory: return "house.fill"
        case .worktree: return "leaf.fill"
        }
    }
}

// MARK: - New Session Dialog

struct NewSessionDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    let repository: Repository
    var onCreateSession: (SessionLocationType) -> Void

    @State private var selectedType: SessionLocationType = .mainDirectory
    @State private var hoveredType: SessionLocationType?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            Text("Where should this session run?")
                .font(Typography.bodySmall)
                .fontWeight(.medium)
                .foregroundStyle(colors.foreground)

            // Options
            VStack(spacing: Spacing.xs) {
                ForEach(SessionLocationType.allCases, id: \.self) { locationType in
                    LocationOption(
                        locationType: locationType,
                        isSelected: selectedType == locationType,
                        isHovered: hoveredType == locationType,
                        onSelect: {
                            selectedType = locationType
                        }
                    )
                    .onHover { hovering in
                        hoveredType = hovering ? locationType : nil
                    }
                }
            }

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.mutedForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)

                Button {
                    onCreateSession(selectedType)
                    isPresented = false
                } label: {
                    Text("Create")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.primary)
            }
        }
        .padding(Spacing.md)
        .frame(width: 280)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color(hex: "0D0D0D").opacity(0.2), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Location Option

struct LocationOption: View {
    @Environment(\.colorScheme) private var colorScheme

    let locationType: SessionLocationType
    let isSelected: Bool
    let isHovered: Bool
    var onSelect: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: locationType.icon)
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(isSelected ? colors.primary : colors.mutedForeground)
                    .frame(width: 20)

                // Title and description
                VStack(alignment: .leading, spacing: 1) {
                    Text(locationType.title)
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.foreground)

                    Text(locationType.description)
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.primary)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : colors.background))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(isSelected ? colors.primary : colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG

#Preview {
    NewSessionDialog(
        isPresented: .constant(true),
        repository: Repository(
            path: "/path/to/repo",
            name: "unbound.computer"
        ),
        onCreateSession: { _ in }
    )
    .padding()
    .background(ThemeColors(.dark).muted.opacity(0.3))
}

#endif
