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
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            Text("Where should this session run?")
                .font(Typography.body)
                .fontWeight(.medium)
                .foregroundStyle(colors.foreground)

            // Options
            VStack(spacing: Spacing.sm) {
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
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

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
        .padding(Spacing.lg)
        .frame(width: 320)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
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
            HStack(spacing: Spacing.md) {
                // Icon
                Image(systemName: locationType.icon)
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(isSelected ? colors.primary : colors.mutedForeground)
                    .frame(width: 24)

                // Title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationType.title)
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.foreground)

                    Text(locationType.description)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.md))
                        .foregroundStyle(colors.primary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : colors.background))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(isSelected ? colors.primary : colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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
    .background(Color.gray.opacity(0.3))
}
