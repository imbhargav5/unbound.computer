//
//  TrustOnboardingView.swift
//  unbound-macos
//
//  Trust onboarding view - placeholder for daemon mode.
//  Device trust is now handled by the daemon.
//

import SwiftUI

struct TrustOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onComplete: (Bool) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // Icon
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(colors.primary)
                .padding(.top, Spacing.xxl)

            // Title & Description
            VStack(spacing: Spacing.lg) {
                Text("Device Trust")
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)

                Text("Device trust is managed by the Unbound daemon.")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Spacer()

            // Continue button
            Button {
                onComplete(true)
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonPrimary(size: .md)
            .frame(maxWidth: 400)
        }
        .padding(Spacing.xxl)
        .frame(width: 500, height: 600)
        .background(colors.background)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: IconSize.lg))
                .foregroundStyle(colors.primary)
                .frame(width: 20)

            Text(text)
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            Spacer()
        }
    }
}

#Preview {
    TrustOnboardingView(onComplete: { _ in })
        .frame(width: 500, height: 600)
}
