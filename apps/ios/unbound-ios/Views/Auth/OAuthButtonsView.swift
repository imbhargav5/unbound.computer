//
//  OAuthButtonsView.swift
//  unbound-ios
//
//  OAuth provider buttons for social sign-in.
//

import SwiftUI

struct OAuthButtonsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.openURL) private var openURL

    @State private var loadingProvider: OAuthProvider?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: AppTheme.spacingM) {
            // GitHub button
            OAuthButton(
                provider: .github,
                isLoading: loadingProvider == .github
            ) {
                signInWith(.github)
            }

            // Google button
            OAuthButton(
                provider: .google,
                isLoading: loadingProvider == .google
            ) {
                signInWith(.google)
            }

            // Error message
            if let errorMessage {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func signInWith(_ provider: OAuthProvider) {
        errorMessage = nil
        loadingProvider = provider

        Task {
            do {
                let url = try await authService.signInWithOAuth(provider: provider)
                await MainActor.run {
                    openURL(url)
                }
            } catch let error as AuthError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                    loadingProvider = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    loadingProvider = nil
                }
            }
        }
    }
}

// MARK: - OAuth Button

private struct OAuthButton: View {
    let provider: OAuthProvider
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.spacingM) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.textPrimary)
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                } else {
                    providerIcon
                        .frame(width: 24, height: 24)
                }

                Text("Continue with \(provider.displayName)")
                    .font(.subheadline.weight(.medium))

                Spacer()
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(AppTheme.spacingM)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .github:
            // GitHub logo using SF Symbol or custom path
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
        case .google:
            // Google logo - using a simple G representation
            Text("G")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - Previews

#Preview {
    VStack {
        OAuthButtonsView()
            .padding()
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}
