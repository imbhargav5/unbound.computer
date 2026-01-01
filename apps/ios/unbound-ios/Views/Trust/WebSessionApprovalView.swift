//
//  WebSessionApprovalView.swift
//  unbound-ios
//
//  View for approving or denying pending web session requests.
//  Web sessions get temporary access to view Claude output.
//

import SwiftUI

/// A pending web session request
struct PendingWebSession: Identifiable {
    let id: String
    let webClientId: String
    let webPublicKey: String
    let requestedAt: Date
    let browserInfo: String
    let ipAddress: String?
    let location: String?
    let permission: WebSessionPermission

    enum WebSessionPermission: String, CaseIterable {
        case viewOnly = "view_only"
        case interact = "interact"
        case fullControl = "full_control"

        var displayName: String {
            switch self {
            case .viewOnly: return "View Only"
            case .interact: return "Interact"
            case .fullControl: return "Full Control"
            }
        }

        var description: String {
            switch self {
            case .viewOnly:
                return "Can view Claude's output but cannot send input"
            case .interact:
                return "Can view output and send messages to Claude"
            case .fullControl:
                return "Full control including pause, resume, and stop"
            }
        }

        var icon: String {
            switch self {
            case .viewOnly: return "eye"
            case .interact: return "text.bubble"
            case .fullControl: return "slider.horizontal.3"
            }
        }
    }
}

/// Approval result
struct WebSessionApprovalResult {
    let sessionId: String
    let approved: Bool
    let sessionKey: Data?
    let expiresAt: Date?
}

struct WebSessionApprovalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deviceTrustService) private var trustService

    let pendingSession: PendingWebSession
    let onResult: (WebSessionApprovalResult) -> Void

    @State private var selectedPermission: PendingWebSession.WebSessionPermission
    @State private var sessionDuration: SessionDuration = .thirtyMinutes
    @State private var isApproving = false
    @State private var showError = false
    @State private var errorMessage = ""

    enum SessionDuration: Int, CaseIterable {
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case oneHour = 60
        case twoHours = 120

        var displayName: String {
            switch self {
            case .fifteenMinutes: return "15 minutes"
            case .thirtyMinutes: return "30 minutes"
            case .oneHour: return "1 hour"
            case .twoHours: return "2 hours"
            }
        }
    }

    init(
        pendingSession: PendingWebSession,
        onResult: @escaping (WebSessionApprovalResult) -> Void
    ) {
        self.pendingSession = pendingSession
        self.onResult = onResult
        self._selectedPermission = State(initialValue: pendingSession.permission)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingXL) {
                    // Header
                    headerSection

                    // Browser info
                    browserInfoSection

                    // Permission selection
                    permissionSection

                    // Duration selection
                    durationSection

                    // Security info
                    securityInfoSection
                }
                .padding()
            }
            .background(AppTheme.backgroundPrimary)
            .navigationTitle("Web Session Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Deny") {
                        denySession()
                    }
                    .foregroundStyle(.red)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomButtons
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: AppTheme.spacingM) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "globe")
                    .font(.system(size: 35))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: AppTheme.spacingXS) {
                Text("Web Session Request")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("A web browser is requesting access to view your Claude session")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var browserInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text("Browser Details")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 0) {
                infoRow(icon: "safari", label: "Browser", value: pendingSession.browserInfo)
                Divider()
                if let ip = pendingSession.ipAddress {
                    infoRow(icon: "network", label: "IP Address", value: ip)
                    Divider()
                }
                if let location = pendingSession.location {
                    infoRow(icon: "location", label: "Location", value: location)
                    Divider()
                }
                infoRow(
                    icon: "clock",
                    label: "Requested",
                    value: pendingSession.requestedAt.formatted(date: .omitted, time: .shortened)
                )
            }
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(12)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text("Permission Level")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: AppTheme.spacingS) {
                ForEach(PendingWebSession.WebSessionPermission.allCases, id: \.rawValue) { permission in
                    permissionOption(permission)
                }
            }
        }
    }

    private func permissionOption(_ permission: PendingWebSession.WebSessionPermission) -> some View {
        Button {
            selectedPermission = permission
        } label: {
            HStack(spacing: AppTheme.spacingM) {
                Image(systemName: permission.icon)
                    .font(.title3)
                    .foregroundStyle(selectedPermission == permission ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(permission.description)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                if selectedPermission == permission {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selectedPermission == permission ? AppTheme.accent : .clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text("Session Duration")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: AppTheme.spacingS) {
                ForEach(SessionDuration.allCases, id: \.rawValue) { duration in
                    durationChip(duration)
                }
            }

            Text("Session will automatically expire after this time")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func durationChip(_ duration: SessionDuration) -> some View {
        Button {
            sessionDuration = duration
        } label: {
            Text(duration.displayName)
                .font(.subheadline)
                .padding(.horizontal, AppTheme.spacingM)
                .padding(.vertical, AppTheme.spacingS)
                .background(
                    Capsule()
                        .fill(sessionDuration == duration ? AppTheme.accent : AppTheme.backgroundSecondary)
                )
                .foregroundStyle(sessionDuration == duration ? .white : AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var securityInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Security")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                securityPoint("End-to-end encrypted with unique session key")
                securityPoint("Session automatically expires after duration")
                securityPoint("You can revoke access at any time")
                securityPoint("No data stored on web browser")
            }
            .padding()
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(12)
        }
    }

    private func securityPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var bottomButtons: some View {
        VStack(spacing: AppTheme.spacingM) {
            Button {
                approveSession()
            } label: {
                HStack {
                    if isApproving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield")
                        Text("Approve Session")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingM)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isApproving)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24)
                Text(label)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Text(value)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .font(.subheadline)
        .padding()
    }

    // MARK: - Actions

    private func approveSession() {
        isApproving = true

        Task {
            do {
                // Generate a random session key
                let sessionKey = CryptoService.shared.randomBytes(count: 32)
                let expiresAt = Date().addingTimeInterval(TimeInterval(sessionDuration.rawValue * 60))

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

                let result = WebSessionApprovalResult(
                    sessionId: pendingSession.id,
                    approved: true,
                    sessionKey: sessionKey,
                    expiresAt: expiresAt
                )

                await MainActor.run {
                    onResult(result)
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isApproving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func denySession() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        let result = WebSessionApprovalResult(
            sessionId: pendingSession.id,
            approved: false,
            sessionKey: nil,
            expiresAt: nil
        )
        onResult(result)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    WebSessionApprovalView(
        pendingSession: PendingWebSession(
            id: UUID().uuidString,
            webClientId: "web-client-123",
            webPublicKey: "base64-public-key",
            requestedAt: Date(),
            browserInfo: "Chrome 120 on macOS",
            ipAddress: "192.168.1.100",
            location: "San Francisco, CA",
            permission: .viewOnly
        )
    ) { result in
        print("Result: \(result.approved)")
    }
}
