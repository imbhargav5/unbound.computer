import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct AccountSettingsView: View {
    @Environment(AuthService.self) private var authService
    @State private var showLogoutAlert = false
    @State private var isLoggingOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingL) {
                // Account header
                accountHeader

                // Settings sections
                settingsSections
            }
            .padding(AppTheme.spacingM)
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        VStack(spacing: AppTheme.spacingM) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: 80, height: 80)

                Text(userInitials)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
            }

            VStack(spacing: AppTheme.spacingXS) {
                Text(authService.currentUserEmail ?? "User")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Pro Plan")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingS)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(AppTheme.toolBadgeBg)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacingL)
    }

    private var userInitials: String {
        guard let email = authService.currentUserEmail else { return "?" }
        let parts = email.components(separatedBy: "@").first ?? email
        let initials = parts.prefix(2).uppercased()
        return String(initials)
    }

    // MARK: - Settings Sections

    private var settingsSections: some View {
        VStack(spacing: AppTheme.spacingM) {
            // Preferences section
            SettingsSection(title: "Preferences") {
                SettingsRow(icon: "bell.badge", title: "Notifications", subtitle: "Manage alerts")
                SettingsRow(icon: "paintbrush", title: "Appearance", subtitle: "Theme & display")
                SettingsRow(icon: "lock.shield", title: "Privacy", subtitle: "Security settings")
            }

            // Support section
            SettingsSection(title: "Support") {
                SettingsRow(icon: "questionmark.circle", title: "Help Center", subtitle: nil)
                SettingsRow(icon: "envelope", title: "Contact Support", subtitle: nil)
                SettingsRow(icon: "doc.text", title: "Terms of Service", subtitle: nil)
            }

            // Logout section
            logoutSection

            // Version info
            HStack {
                Text("Version 1.0.0 (Build 1)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, AppTheme.spacingM)
        }
    }

    // MARK: - Logout Section

    private var logoutSection: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack(spacing: AppTheme.spacingM) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(width: 24)

                Text("Sign Out")
                    .font(.body)
                    .foregroundStyle(.red)

                Spacer()

                if isLoggingOut {
                    ProgressView()
                        .tint(.red)
                }
            }
            .padding(AppTheme.spacingM)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .disabled(isLoggingOut)
        .alert("Sign Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to sign in again to access your sessions.")
        }
    }

    private func performLogout() {
        isLoggingOut = true

        Task {
            do {
                try await authService.signOut()
                // The app will automatically navigate to the auth screen
                // because the auth state changes to .unauthenticated
            } catch {
                logger.error("Logout failed: \(error)")
                await MainActor.run {
                    isLoggingOut = false
                }
            }
        }
    }

}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.leading, AppTheme.spacingXS)

            VStack(spacing: 1) {
                content()
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AccountSettingsView()
    }
    .tint(AppTheme.accent)
}
