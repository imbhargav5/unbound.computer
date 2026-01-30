//
//  OnboardingView.swift
//  unbound-macos
//
//  2-panel login view matching web app design language.
//  Left panel: Auth form, Right panel: Illustration
//

import SwiftUI

// MARK: - Onboarding State

enum OnboardingMode: Equatable {
    case signIn
    case signUp
    case magicLink
    case magicLinkSent(email: String)
    case forgotPassword
    case forgotPasswordSent(email: String)
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: OnboardingMode = .signIn
    @State private var errorMessage: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Panel - Auth Form
            authFormPanel
                .frame(minWidth: 400, maxWidth: 500)

            // Divider
            Rectangle()
                .fill(colors.border.opacity(0.5))
                .frame(width: 1)

            // Right Panel - Illustration
            AuthIllustrationView()
                .frame(maxWidth: .infinity)
        }
        .background(Color.black)
    }

    // MARK: - Auth Form Panel

    private var authFormPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Logo
                logoSection

                // Content based on mode
                switch mode {
                case .signIn:
                    signInContent
                case .signUp:
                    signUpContent
                case .magicLink:
                    magicLinkContent
                case .magicLinkSent(let email):
                    magicLinkSentContent(email: email)
                case .forgotPassword:
                    forgotPasswordContent
                case .forgotPasswordSent(let email):
                    forgotPasswordSentContent(email: email)
                }
            }
            .padding(.horizontal, Spacing.xxxxl)
            .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        HStack(spacing: Spacing.md) {
            // Terminal icon
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "terminal.fill")
                        .font(.system(size: IconSize.lg))
                        .foregroundStyle(.white)
                )

            Text("Unbound")
                .font(Typography.h3)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Sign In Content

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Welcome back")
                    .font(Typography.headline)
                    .foregroundStyle(.white)

                Text("Sign in to continue to Unbound")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // OAuth buttons
            OAuthButtonsView()

            // Divider
            dividerWithText("or continue with email")

            // Email form
            SignInFormView(
                onMagicLink: { mode = .magicLink },
                onForgotPassword: { mode = .forgotPassword },
                errorMessage: errorMessage
            )

            // Footer
            HStack(spacing: Spacing.xs) {
                Text("Don't have an account?")
                    .font(Typography.bodySmall)
                    .foregroundStyle(.white.opacity(0.4))

                Button("Sign up") {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        mode = .signUp
                        errorMessage = nil
                    }
                }
                .buttonStyle(.plain)
                .font(Typography.bodySmall)
                .foregroundStyle(.white.opacity(0.7))
                .onHover { hovering in
                    // Hover effect handled by cursor
                }
            }
        }
    }

    // MARK: - Sign Up Content

    private var signUpContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Create account")
                    .font(Typography.headline)
                    .foregroundStyle(.white)

                Text("Get started with Unbound")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // OAuth buttons
            OAuthButtonsView()

            // Divider
            dividerWithText("or continue with email")

            // Sign up form
            SignUpFormView(errorMessage: errorMessage)

            // Footer
            HStack(spacing: Spacing.xs) {
                Text("Already have an account?")
                    .font(Typography.bodySmall)
                    .foregroundStyle(.white.opacity(0.4))

                Button("Sign in") {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        mode = .signIn
                        errorMessage = nil
                    }
                }
                .buttonStyle(.plain)
                .font(Typography.bodySmall)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Magic Link Content

    private var magicLinkContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Back button
            Button {
                withAnimation { mode = .signIn }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .font(Typography.bodySmall)
                .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Magic link")
                    .font(Typography.headline)
                    .foregroundStyle(.white)

                Text("We'll send you a magic link to sign in")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Magic link form
            MagicLinkFormView { email in
                withAnimation {
                    mode = .magicLinkSent(email: email)
                }
            }
        }
    }

    // MARK: - Magic Link Sent Content

    private func magicLinkSentContent(email: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Success icon
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: IconSize.xxl, weight: .medium))
                        .foregroundStyle(.white)
                )

            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Check your email")
                    .font(Typography.headline)
                    .foregroundStyle(.white)

                Text("We sent a magic link to")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.5))

                Text(email)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(.white)
            }

            // Instructions
            VStack(alignment: .leading, spacing: Spacing.md) {
                instructionRow(number: "1", text: "Open the email on this device")
                instructionRow(number: "2", text: "Click the magic link to sign in")
            }
            .padding(Spacing.lg)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Back link
            Button {
                withAnimation { mode = .signIn }
            } label: {
                Text("Back to sign in")
                    .font(Typography.bodySmall)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Forgot Password Content

    private var forgotPasswordContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Back button
            Button {
                withAnimation { mode = .signIn }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .font(Typography.bodySmall)
                .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Reset password")
                    .font(Typography.headline)
                    .foregroundStyle(.white)

                Text("Enter your email to receive a reset link")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Reset password form
            ForgotPasswordFormView { email in
                withAnimation {
                    mode = .forgotPasswordSent(email: email)
                }
            }
        }
    }

    // MARK: - Forgot Password Sent Content

    private func forgotPasswordSentContent(email: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Success icon
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "envelope")
                        .font(.system(size: IconSize.xxl, weight: .medium))
                        .foregroundStyle(.white)
                )

            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Check your email")
                    .font(Typography.headline)
                    .foregroundStyle(.white)

                Text("We sent a password reset link to")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.5))

                Text(email)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(.white)
            }

            // Back link
            Button {
                withAnimation { mode = .signIn }
            } label: {
                Text("Back to sign in")
                    .font(Typography.bodySmall)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func dividerWithText(_ text: String) -> some View {
        HStack(spacing: Spacing.lg) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize()

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(number)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                )

            Text(text)
                .font(Typography.bodySmall)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
        .frame(width: 1000, height: 700)
}
