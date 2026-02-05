//
//  RemoveRepositoryDialog.swift
//  unbound-macos
//
//  Confirmation dialog for removing a repository from the sidebar.
//

import SwiftUI

struct RemoveRepositoryDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    let repository: Repository
    let isRemoving: Bool
    let errorMessage: String?
    var onConfirm: () -> Void

    @State private var confirmationText: String = ""
    @FocusState private var isConfirmationFocused: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var isConfirmationValid: Bool {
        confirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "confirm"
    }

    private var canConfirm: Bool {
        isConfirmationValid && !isRemoving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "trash")
                    .font(.system(size: IconSize.lg, weight: .semibold))
                    .foregroundStyle(colors.destructive)

                Text("Remove Repository?")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

                Spacer()
            }

            // Body copy
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("This will remove \"\(repository.name)\" from Unbound. The repository files will not be deleted.")
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)

                Text(repository.displayPath)
                    .font(Typography.mono)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Input
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Type \"confirm\" to continue")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                ShadcnTextField("confirm", text: $confirmationText, variant: .filled)
                    .autocorrectionDisabled()
                    .disabled(isRemoving)
                    .focused($isConfirmationFocused)
                    .onSubmit {
                        if canConfirm {
                            onConfirm()
                        }
                    }

                Text("Confirmation is case-insensitive")
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
            }

            if let errorMessage {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.destructive)

                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(colors.destructive)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colors.destructive.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            // Actions
            HStack(spacing: Spacing.sm) {
                Spacer()

                Button("Cancel") {
                    if !isRemoving {
                        isPresented = false
                    }
                }
                .buttonSecondary(size: .sm)
                .disabled(isRemoving)

                Button {
                    onConfirm()
                } label: {
                    Text(isRemoving ? "Removing..." : "Remove")
                        .fontWeight(.medium)
                }
                .buttonDestructive(size: .sm)
                .disabled(!canConfirm)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 360)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
        .elevation(Elevation.lg)
        .onAppear {
            isConfirmationFocused = true
        }
    }
}

struct RemoveRepositoryOverlay: View {
    @Binding var isPresented: Bool

    let repository: Repository
    let isRemoving: Bool
    let errorMessage: String?
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isRemoving {
                        isPresented = false
                    }
                }

            RemoveRepositoryDialog(
                isPresented: $isPresented,
                repository: repository,
                isRemoving: isRemoving,
                errorMessage: errorMessage,
                onConfirm: onConfirm
            )
            .transition(.opacity)
        }
    }
}

#Preview {
    RemoveRepositoryOverlay(
        isPresented: .constant(true),
        repository: Repository(path: "/Users/example/unbound", name: "unbound.computer"),
        isRemoving: false,
        errorMessage: nil,
        onConfirm: {}
    )
    .frame(width: 800, height: 600)
}
