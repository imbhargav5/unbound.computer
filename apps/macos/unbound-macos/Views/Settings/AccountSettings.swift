//
//  AccountSettings.swift
//  unbound-macos
//
//  Account settings showing user info and sign out option.
//

import SwiftUI

private enum BillingUsagePanelState: Equatable {
    case loading
    case loaded(DaemonBillingUsageStatusResponse)
    case unavailable
    case error(String)
}

struct AccountSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var billingUsageState: BillingUsagePanelState = .loading
    @State private var isRefreshingBilling = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        SettingsPageContainer(title: "Account", subtitle: "Manage your account and billing.") {
            profileSection

            ShadcnDivider(.horizontal)

            billingSection

            ShadcnDivider(.horizontal)

            actionsSection
        }
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
        .task(id: appState.currentUserId) {
            await refreshBillingUsage(forceLoading: true)
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
                            .font(GeistFont.mono(size: 24, weight: .semibold))
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

                        if let status = currentBillingStatus {
                            Text("• \(status.plan.capitalized) plan")
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                        }
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

    // MARK: - Billing Section

    private var billingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Billing & Usage")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

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
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.mutedForeground)
                .disabled(isRefreshingBilling)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                switch billingUsageState {
                case .loading:
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading billing usage from daemon…")
                            .font(Typography.body)
                            .foregroundStyle(colors.mutedForeground)
                    }
                case .loaded(let response):
                    if let status = response.status {
                        billingStatusContent(status: status, stale: response.stale)
                    } else {
                        unavailableBillingContent
                    }
                case .unavailable:
                    unavailableBillingContent
                case .error(let message):
                    Label("Unable to load billing usage", systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.body)
                        .foregroundStyle(colors.destructive)
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                Text("Usage enforcement is eventually consistent. Status may lag by up to ~5 minutes.")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Button(billingActionTitle) {
                    openURL(Config.apiURL.appendingPathComponent("pricing"))
                }
                .buttonPrimary(size: .md)
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

    private func billingStatusContent(status: DaemonBillingUsageStatus, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(billingStatusTitle(for: status.enforcementState), systemImage: billingStatusIcon(for: status.enforcementState))
                .font(Typography.body)
                .foregroundStyle(billingStatusColor(for: status.enforcementState))

            Text("\(status.plan.capitalized) plan • \(status.commandsUsed)/\(status.commandsLimit) commands used • \(status.commandsRemaining) remaining")
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)

            if stale {
                Text("Usage snapshot is stale. Refreshing may take up to ~5 minutes.")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }
        }
    }

    private var unavailableBillingContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Billing usage unavailable", systemImage: "questionmark.circle")
                .font(Typography.body)
                .foregroundStyle(colors.mutedForeground)
            Text("We could not resolve a recent usage snapshot for this device yet.")
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
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

    private var currentBillingStatus: DaemonBillingUsageStatus? {
        if case .loaded(let response) = billingUsageState {
            return response.status
        }
        return nil
    }

    private var billingActionTitle: String {
        guard let status = currentBillingStatus else {
            return "Manage Billing"
        }
        if status.plan.lowercased() == "free" || status.enforcementState != .ok {
            return "Upgrade Plan"
        }
        return "Manage Billing"
    }

    private func billingStatusTitle(for enforcementState: DaemonBillingEnforcementState) -> String {
        switch enforcementState {
        case .ok:
            return "Usage in range"
        case .nearLimit:
            return "Near command limit"
        case .overQuota:
            return "Command limit reached"
        }
    }

    private func billingStatusIcon(for enforcementState: DaemonBillingEnforcementState) -> String {
        switch enforcementState {
        case .ok:
            return "checkmark.circle.fill"
        case .nearLimit:
            return "exclamationmark.triangle.fill"
        case .overQuota:
            return "xmark.octagon.fill"
        }
    }

    private func billingStatusColor(for enforcementState: DaemonBillingEnforcementState) -> Color {
        switch enforcementState {
        case .ok:
            return colors.success
        case .nearLimit:
            return Color.orange
        case .overQuota:
            return colors.destructive
        }
    }

    @MainActor
    private func refreshBillingUsage(forceLoading: Bool = false) async {
        if forceLoading {
            billingUsageState = .loading
        }

        guard appState.isAuthenticated, appState.isDaemonConnected else {
            billingUsageState = .unavailable
            isRefreshingBilling = false
            return
        }

        isRefreshingBilling = true
        defer {
            isRefreshingBilling = false
        }

        do {
            let response = try await appState.daemonClient.getBillingUsageStatus()
            if response.available {
                billingUsageState = .loaded(response)
            } else {
                billingUsageState = .unavailable
            }
        } catch {
            billingUsageState = .error(error.localizedDescription)
        }
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
