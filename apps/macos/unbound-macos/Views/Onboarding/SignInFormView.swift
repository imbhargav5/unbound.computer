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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Email field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Email")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.5))

                emailField
            }

            // Password field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Password")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.5))

                passwordField
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Color(hex: "ef4444"))
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
                .background(Color.white.opacity(0.05))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Button("Forgot password?") {
                    onForgotPassword()
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var emailField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "envelope")
                .font(.system(size: IconSize.md))
                .foregroundStyle(focusedField == .email ? .white.opacity(0.6) : .white.opacity(0.3))

            TextField("you@example.com", text: $email)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(.white)
                .focused($focusedField, equals: .email)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .onSubmit {
                    focusedField = .password
                }
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    focusedField == .email ? Color.white.opacity(0.2) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock")
                .font(.system(size: IconSize.md))
                .foregroundStyle(focusedField == .password ? .white.opacity(0.6) : .white.opacity(0.3))

            Group {
                if showPassword {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(.white)
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
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    focusedField == .password ? Color.white.opacity(0.2) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    private func signIn() {
        isLoading = true

        Task {
            do {
                // Use daemon for email/password login
                try await appState.login(provider: "email", email: email)
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
    .background(Color.black)
    .frame(width: 400)
}
