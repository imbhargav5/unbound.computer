//
//  SignInFormView.swift
//  unbound-macos
//
//  Email/password sign in form with magic link option.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.auth")

struct SignInFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showPassword = false

    @FocusState private var focusedField: Field?

    var onMagicLink: () -> Void
    var onForgotPassword: () -> Void
    var errorMessage: String?

    enum Field {
        case email, password
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Email field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Email")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                emailField
            }

            // Password field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Password")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                passwordField
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(colors.destructive)
            }

            // Sign in button
            Button {
                signIn()
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(.circular)
                    }
                    Text(isLoading ? "Signing in..." : "Sign in")
                        .font(Typography.label)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: IconSize.md))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.horizontal, Spacing.lg)
                .background(colors.surface2)
                .foregroundStyle(colors.foreground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

            // Links row
            HStack {
                Button("Use magic link") {
                    onMagicLink()
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)

                Spacer()

                Button("Forgot password?") {
                    onForgotPassword()
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
            }
        }
    }

    private var emailField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "envelope")
                .font(.system(size: IconSize.md))
                .foregroundStyle(focusedField == .email ? colors.sidebarText : colors.inactive)

            TextField("you@example.com", text: $email)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(colors.foreground)
                .focused($focusedField, equals: .email)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .onSubmit {
                    focusedField = .password
                }
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
        .background(colors.surface2.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    focusedField == .email ? colors.borderSecondary : colors.border,
                    lineWidth: 1
                )
        )
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock")
                .font(.system(size: IconSize.md))
                .foregroundStyle(focusedField == .password ? colors.sidebarText : colors.inactive)

            Group {
                if showPassword {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(colors.foreground)
            .focused($focusedField, equals: .password)
            .onSubmit {
                if !email.isEmpty && !password.isEmpty {
                    signIn()
                }
            }

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(colors.inactive)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
        .background(colors.surface2.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    focusedField == .password ? colors.borderSecondary : colors.border,
                    lineWidth: 1
                )
        )
    }

    private func signIn() {
        isLoading = true

        Task {
            do {
                // Use daemon for email/password login
                try await appState.loginWithPassword(email: email, password: password)
            } catch {
                logger.error("Sign in error: \(error)")
            }
            isLoading = false
        }
    }
}

#Preview {
    SignInFormView(
        onMagicLink: {},
        onForgotPassword: {},
        errorMessage: nil
    )
    .environment(AppState())
    .padding(Spacing.xxxxl)
    .background(ThemeColors(.dark).background)
    .frame(width: 400)
}
