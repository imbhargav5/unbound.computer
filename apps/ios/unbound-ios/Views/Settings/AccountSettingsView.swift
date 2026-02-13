import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct AccountSettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.openURL) private var openURL
    @State private var showLogoutAlert = false
    @State private var isLoggingOut = false
    @State private var billingUsageState: BillingUsageCardState = .loading
    @State private var isRefreshingBilling = false

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
        .task(id: authService.currentUserId) {
            await refreshBillingUsage(forceLoading: true)
        }
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

                Text(planBadgeTitle)
                    .font(.subheadline)
                    .foregroundStyle(planBadgeColor)
                    .padding(.horizontal, AppTheme.spacingS)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(planBadgeBackgroundColor)
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

    private var planBadgeTitle: String {
        guard let status = currentBillingStatus else {
            switch billingUsageState {
            case .loading:
                return "Loading plan…"
            case .error:
                return "Plan unavailable"
            default:
                return "Free Plan"
            }
        }
        return status.plan == .paid ? "Paid Plan" : "Free Plan"
    }

    private var planBadgeColor: Color {
        switch billingUsageState {
        case .nearLimit:
            return .orange
        case .overLimit:
            return .red
        default:
            return AppTheme.accent
        }
    }

    private var planBadgeBackgroundColor: Color {
        switch billingUsageState {
        case .nearLimit:
            return Color.orange.opacity(0.15)
        case .overLimit:
            return Color.red.opacity(0.15)
        default:
            return AppTheme.toolBadgeBg
        }
    }

    // MARK: - Settings Sections

    private var settingsSections: some View {
        VStack(spacing: AppTheme.spacingM) {
            billingUsageSection

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

    // MARK: - Billing & Usage

    private var billingUsageSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            HStack {
                Text("Billing & Usage")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.leading, AppTheme.spacingXS)

                Spacer()

                Button {
                    Task {
                        await refreshBillingUsage()
                    }
                } label: {
                    if isRefreshingBilling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                .disabled(isRefreshingBilling)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                switch billingUsageState {
                case .loading:
                    HStack(spacing: AppTheme.spacingS) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading your current plan and usage…")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                case .active(let status):
                    usageSummaryRow(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Usage in range",
                        subtitle: usageSubtitle(for: status)
                    )
                case .nearLimit(let status):
                    usageSummaryRow(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        title: "Near command limit",
                        subtitle: usageSubtitle(for: status)
                    )
                case .overLimit(let status):
                    usageSummaryRow(
                        icon: "xmark.octagon.fill",
                        iconColor: .red,
                        title: "Command limit reached",
                        subtitle: usageSubtitle(for: status)
                    )
                case .error(let message):
                    usageSummaryRow(
                        icon: "exclamationmark.circle.fill",
                        iconColor: .red,
                        title: "Unable to load billing usage",
                        subtitle: message
                    )
                }

                Text("Quota status can lag slightly. Usage may take up to ~5 minutes to fully refresh.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Button {
                    openURL(Config.apiURL.appendingPathComponent("pricing"))
                } label: {
                    Text(billingActionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingS)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.spacingM)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }

    private func usageSummaryRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var currentBillingStatus: BillingUsageStatus? {
        switch billingUsageState {
        case .active(let status), .nearLimit(let status), .overLimit(let status):
            return status
        default:
            return nil
        }
    }

    private var billingActionTitle: String {
        guard let status = currentBillingStatus else {
            return "Manage Billing"
        }
        if status.plan == .free || status.enforcementState != .ok {
            return "Upgrade Plan"
        }
        return "Manage Billing"
    }

    private func usageSubtitle(for status: BillingUsageStatus) -> String {
        let planName = status.plan == .paid ? "Paid" : "Free"
        return "\(planName) plan • \(status.commandsUsed)/\(status.commandsLimit) commands used • \(status.commandsRemaining) remaining"
    }

    @MainActor
    private func refreshBillingUsage(forceLoading: Bool = false) async {
        if forceLoading {
            billingUsageState = .loading
        }
        isRefreshingBilling = true
        defer {
            isRefreshingBilling = false
        }

        do {
            let status = try await BillingUsageService.fetchUsageStatus(authService: authService)
            billingUsageState = BillingUsageCardState.from(status: status)
        } catch {
            logger.error("Failed to load billing usage status: \(error)")
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            billingUsageState = .error(message)
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
