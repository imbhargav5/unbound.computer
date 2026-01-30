//
//  SignUpFormView.swift
//  unbound-ios
//
//  Email/password sign up form.
//

import SwiftUI

struct SignUpFormView: View {
    @Environment(AuthService.self) private var authService

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEmailConfirmation = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case email
        case password
        case confirmPassword
    }

    var body: some View {
        VStack(spacing: AppTheme.spacingM) {
            // Email field
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text("Email")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "envelope")
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 20)

                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                }
                .padding(AppTheme.spacingM)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(focusedField == .email ? AppTheme.accent : AppTheme.cardBorder, lineWidth: 1)
                )
            }

            // Password field
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text("Password")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "lock")
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 20)

                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .confirmPassword
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .padding(AppTheme.spacingM)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(focusedField == .password ? AppTheme.accent : AppTheme.cardBorder, lineWidth: 1)
                )

                // Password requirements
                if !password.isEmpty {
                    passwordRequirements
                }
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text("Confirm Password")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "lock.badge.checkmark")
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 20)

                    Group {
                        if showPassword {
                            TextField("Confirm password", text: $confirmPassword)
                        } else {
                            SecureField("Confirm password", text: $confirmPassword)
                        }
                    }
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmPassword)
                    .submitLabel(.go)
                    .onSubmit {
                        signUp()
                    }
                }
                .padding(AppTheme.spacingM)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(focusedField == .confirmPassword ? AppTheme.accent : AppTheme.cardBorder, lineWidth: 1)
                )

                // Password match indicator
                if !confirmPassword.isEmpty {
                    HStack(spacing: AppTheme.spacingXS) {
                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                        Text(passwordsMatch ? "Passwords match" : "Passwords don't match")
                            .font(.caption)
                    }
                    .foregroundStyle(passwordsMatch ? .green : .red)
                }
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sign up button
            Button {
                signUp()
            } label: {
                HStack(spacing: AppTheme.spacingS) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color(.systemBackground))
                            .scaleEffect(0.8)
                    }
                    Text("Create Account")
                        .font(.headline)
                }
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingM)
                .background(isFormValid ? AppTheme.accentGradient : LinearGradient(colors: [AppTheme.textTertiary], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            }
            .disabled(!isFormValid || isLoading)

            // Terms notice
            Text("By creating an account, you agree to our Terms of Service and Privacy Policy.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .alert("Check Your Email", isPresented: $showEmailConfirmation) {
            Button("OK") {}
        } message: {
            Text("We've sent a confirmation link to \(email). Please check your email to verify your account.")
        }
    }

    // MARK: - Password Requirements

    private var passwordRequirements: some View {
        VStack(alignment: .leading, spacing: 2) {
            PasswordRequirementRow(
                text: "At least 8 characters",
                isMet: password.count >= 8
            )
        }
        .padding(.top, AppTheme.spacingXS)
    }

    // MARK: - Validation

    private var isEmailValid: Bool {
        !email.isEmpty && email.contains("@") && email.contains(".")
    }

    private var isPasswordValid: Bool {
        password.count >= 8
    }

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var isFormValid: Bool {
        isEmailValid && isPasswordValid && passwordsMatch
    }

    // MARK: - Actions

    private func signUp() {
        guard isFormValid else { return }

        errorMessage = nil
        isLoading = true
        focusedField = nil

        Task {
            do {
                try await authService.signUpWithEmail(email: email, password: password)
            } catch let error as AuthError {
                await MainActor.run {
                    if case .emailNotConfirmed = error {
                        showEmailConfirmation = true
                    } else {
                        errorMessage = error.errorDescription
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Password Requirement Row

private struct PasswordRequirementRow: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: AppTheme.spacingXS) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(isMet ? .green : AppTheme.textTertiary)

            Text(text)
                .font(.caption2)
                .foregroundStyle(isMet ? AppTheme.textSecondary : AppTheme.textTertiary)
        }
    }
}

// MARK: - Previews

#Preview {
    VStack {
        SignUpFormView()
            .padding()
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}
