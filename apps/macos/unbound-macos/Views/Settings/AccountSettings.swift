//
//  AccountSettings.swift
//  unbound-macos
//
//  Account settings showing user info and sign out option.
//

import SwiftUI

struct AccountSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Header
                Text("Account")
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)

                // Profile section
                profileSection

                ShadcnDivider(.horizontal)

                // Account actions section
                actionsSection
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out") {
                signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Profile")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            HStack(spacing: Spacing.lg) {
                // Avatar
                Circle()
                    .fill(colors.primary)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(avatarInitial)
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .foregroundStyle(colors.primaryForeground)
                    )

                // User info
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let email = appState.currentUserEmail {
                        Text(email)
                            .font(Typography.body)
                            .foregroundStyle(colors.foreground)
                    } else {
                        Text("Unknown user")
                            .font(Typography.body)
                            .foregroundStyle(colors.mutedForeground)
                    }

                    // Provider badge
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.success)

                        Text("Authenticated")
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                }

                Spacer()
            }
            .padding(Spacing.lg)
            .background(colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Account Actions")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Button {
                showSignOutConfirmation = true
            } label: {
                HStack {
                    if isSigningOut {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    Text(isSigningOut ? "Signing out..." : "Sign Out")
                }
            }
            .buttonDestructive(size: .md)
            .disabled(isSigningOut)
        }
    }

    // MARK: - Helpers

    private var avatarInitial: String {
        if let email = appState.currentUserEmail,
           let firstChar = email.first {
            return String(firstChar).uppercased()
        }
        return "U"
    }

    private func signOut() {
        isSigningOut = true

        Task {
            // Logout via daemon (handles everything including relay disconnect)
            try? await appState.logout()

            isSigningOut = false
        }
    }
}

#Preview {
    AccountSettings()
        .environment(AppState())
        .frame(width: 500, height: 600)
}
