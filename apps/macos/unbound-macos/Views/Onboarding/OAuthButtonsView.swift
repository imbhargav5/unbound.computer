//
//  OAuthButtonsView.swift
//  unbound-macos
//
//  OAuth provider buttons matching web app design.
//  GitHub: White background, black text
//  Google: Transparent with border
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.auth")

// MARK: - OAuth Provider

/// Supported OAuth providers for authentication
enum OAuthProvider: String, CaseIterable {
    case github = "github"
    case google = "google"

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .google: return "Google"
        }
    }
}

struct OAuthButtonsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var loadingProvider: OAuthProvider?
    @State private var hoveredProvider: OAuthProvider?

    var body: some View {
        VStack(spacing: Spacing.md) {
            // GitHub Button (Primary style - white bg)
            oauthButton(provider: .github, isPrimary: true)

            // Google Button (Outline style)
            oauthButton(provider: .google, isPrimary: false)
        }
    }

    private func oauthButton(provider: OAuthProvider, isPrimary: Bool) -> some View {
        Button {
            signIn(with: provider)
        } label: {
            HStack(spacing: Spacing.md) {
                providerIcon(provider)

                Text("Continue with \(provider.displayName)")
                    .font(Typography.label)

                Spacer()

                if loadingProvider == provider {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(.circular)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, Spacing.lg)
            .background(isPrimary ? Color.white : Color.clear)
            .foregroundStyle(isPrimary ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        isPrimary ? Color.clear : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .opacity(hoveredProvider == provider ? (isPrimary ? 0.9 : 1) : 1)
            .background(
                hoveredProvider == provider && !isPrimary ?
                    Color.white.opacity(0.05) : Color.clear
            )
        }
        .buttonStyle(.plain)
        .disabled(loadingProvider != nil)
        .onHover { hovering in
            hoveredProvider = hovering ? provider : nil
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: OAuthProvider) -> some View {
        switch provider {
        case .github:
            // GitHub logo approximation using SF Symbol
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: IconSize.lg, weight: .medium))
        case .google:
            // Google "G" approximation
            Text("G")
                .font(.system(size: IconSize.lg, weight: .bold, design: .rounded))
        }
    }

    private func signIn(with provider: OAuthProvider) {
        loadingProvider = provider

        Task {
            do {
                // Use daemon for OAuth login
                try await appState.loginWithProvider(provider.rawValue)
            } catch {
                logger.error("OAuth error: \(error)")
            }
            loadingProvider = nil
        }
    }
}

#Preview {
    OAuthButtonsView()
        .environment(AppState())
        .padding(Spacing.xxxxl)
        .background(Color.black)
        .frame(width: 400)
}
