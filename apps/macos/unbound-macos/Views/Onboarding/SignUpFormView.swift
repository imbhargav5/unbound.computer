//
//  SignUpFormView.swift
//  unbound-macos
//
//  Email/password sign up form.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.auth")

struct SignUpFormView: View {
    @Environment(AppState.self) private var appState

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showPassword = false
    @State private var localError: String?

    @FocusState private var focusedField: Field?

    var errorMessage: String?

    enum Field {
        case email, password, confirmPassword
    }

    private var displayError: String? {
        localError ?? errorMessage
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

                Text("Must be at least 8 characters")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.3))
            }

            // Confirm Password field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Confirm Password")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.5))

                confirmPasswordField
            }

            // Error message
            if let error = displayError {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Color(hex: "ef4444"))
            }

            // Sign up button
            Button {
                signUp()
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(.circular)
                    }
                    Text(isLoading ? "Creating account..." : "Create account")
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
            .disabled(isLoading || !isFormValid)
            .opacity(isFormValid ? 1 : 0.5)
        }
    }

    private var isFormValid: Bool {
        !email.isEmpty && password.count >= 8 && password == confirmPassword
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
                focusedField = .confirmPassword
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

    private var confirmPasswordField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock")
                .font(.system(size: IconSize.md))
                .foregroundStyle(focusedField == .confirmPassword ? .white.opacity(0.6) : .white.opacity(0.3))

            Group {
                if showPassword {
                    TextField("Confirm password", text: $confirmPassword)
                } else {
                    SecureField("Confirm password", text: $confirmPassword)
                }
            }
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(.white)
            .focused($focusedField, equals: .confirmPassword)
            .onSubmit {
                if isFormValid {
                    signUp()
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    focusedField == .confirmPassword ? Color.white.opacity(0.2) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    private func signUp() {
        localError = nil

        // Validate passwords match
        guard password == confirmPassword else {
            localError = "Passwords don't match"
            return
        }

        isLoading = true

        Task {
            do {
                // Use daemon for email signup
                try await appState.loginWithProvider("email", email: email)
            } catch {
                logger.error("Sign up error: \(error)")
            }
            isLoading = false
        }
    }
}

#Preview {
    SignUpFormView(errorMessage: nil)
        .environment(AppState())
        .padding(Spacing.xxxxl)
        .background(Color.black)
        .frame(width: 400)
}
