//
//  TrustOnboardingView.swift
//  unbound-ios
//
//  Onboarding view for marking device as trusted.
//  Shown on first login after device registration.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.auth")

struct TrustOnboardingView: View {
    let onComplete: (Bool) -> Void

    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            // Icon
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppTheme.accent)
                .padding(.top, AppTheme.spacingXL)

            // Title
            Text("Trust This Device?")
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)

            // Description
            VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                Text("Marking this device as trusted allows you to:")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)

                FeatureRow(
                    icon: "bolt.fill",
                    text: "Access sensitive operations"
                )
                FeatureRow(
                    icon: "lock.shield.fill",
                    text: "Manage security settings"
                )
                FeatureRow(
                    icon: "arrow.triangle.branch",
                    text: "Approve other devices"
                )
            }
            .padding(.horizontal, AppTheme.spacingL)

            Spacer()

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, AppTheme.spacingL)
                    .multilineTextAlignment(.center)
            }

            // Trust button
            Button {
                handleTrust(true)
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                        }
                    Text(isProcessing ? "Setting up..." : "Trust This Device")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingM)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(isProcessing)
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundPrimary)
    }

    private func handleTrust(_ trust: Bool) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let service = DeviceTrustStatusService.shared

                // Set trust status
                try await service.setTrusted(trust)

                // Mark prompt as seen
                try await service.markTrustPromptSeen()

                await MainActor.run {
                    isProcessing = false
                    onComplete(trust)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()
        }
    }
}

#Preview {
    TrustOnboardingView { trusted in
        logger.debug("Trust status: \(trusted)")
    }
}
