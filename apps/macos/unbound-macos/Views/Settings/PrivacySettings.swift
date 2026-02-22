//
//  PrivacySettings.swift
//  unbound-macos
//
//  Privacy settings - E2E encryption information
//

import SwiftUI

struct PrivacySettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        SettingsPageContainer(title: "Privacy", subtitle: "Your data is protected with end-to-end encryption.") {
            encryptionHeroCard

            ShadcnDivider(.horizontal)

            technicalDetailsSection

            ShadcnDivider(.horizontal)

            openSourceSection
        }
    }

    // MARK: - Hero Card

    private var encryptionHeroCard: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(colors.success)

            Text("End-to-End Encrypted")
                .font(Typography.h3)
                .foregroundStyle(colors.foreground)

            Text("Messages are encrypted before leaving your device. Only your devices can decrypt them — our servers never see your content.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.muted.opacity(0.3))
        )
    }

    // MARK: - Technical Details

    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Technical Details")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(spacing: 0) {
                technicalDetailRow(
                    label: "Encryption",
                    value: "ChaCha20-Poly1305",
                    detail: "Authenticated AEAD cipher",
                    showTopBorder: false
                )
                technicalDetailRow(
                    label: "Key Exchange",
                    value: "X25519",
                    detail: "Elliptic Curve Diffie-Hellman"
                )
                technicalDetailRow(
                    label: "Key Derivation",
                    value: "HKDF-SHA256",
                    detail: "HMAC-based key derivation"
                )
                technicalDetailRow(
                    label: "Cloud Sync",
                    value: "Encrypted",
                    detail: "Data encrypted before upload"
                )
            }
            .background(colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(colors.border, lineWidth: BorderWidth.default)
            )
        }
    }

    private func technicalDetailRow(
        label: String,
        value: String,
        detail: String,
        showTopBorder: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            if showTopBorder {
                Rectangle()
                    .fill(colors.border)
                    .frame(height: BorderWidth.default)
            }

            HStack {
                Text(label)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: 100, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(value)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(colors.foreground)

                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Open Source

    private var openSourceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Open Source")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Our encryption code is fully open source and auditable. You can review the implementation yourself.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)

            Button {
                if let url = URL(string: "https://github.com/imbhargav5/unbound.computer/tree/main/apps/daemon/crates/daemon-config-and-utils/src") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: IconSize.sm))
                    Text("View Source Code")
                }
            }
            .buttonOutline(size: .sm)
        }
    }
}

#if DEBUG

#Preview {
    PrivacySettings()
        .frame(width: 500, height: 600)
}

#endif
