//
//  ForgotPasswordFormView.swift
//  unbound-ios
//
//  Password reset form that sends a reset link via email.
//

import SwiftUI

struct ForgotPasswordFormView: View {
    @Environment(AuthService.self) private var authService

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var emailSent = false

    @FocusState private var isEmailFocused: Bool

    var onBackToSignIn: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacingM) {
            if emailSent {
                // Success state
                VStack(spacing: AppTheme.spacingL) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)

                    VStack(spacing: AppTheme.spacingS) {
                        Text("Check Your Email")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("We've sent a password reset link to:")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        Text(email)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }

                    Button {
                        onBackToSignIn()
                    } label: {
                        Text("Back to Sign In")
                            .font(.headline)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacingM)
                            .background(AppTheme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                    }
                }
            } else {
                // Form state
                VStack(spacing: AppTheme.spacingM) {
                    // Header
                    VStack(spacing: AppTheme.spacingS) {
                        Text("Reset Password")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Enter your email address and we'll send you a link to reset your password.")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

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
                                .focused($isEmailFocused)
                                .submitLabel(.send)
                                .onSubmit {
                                    sendResetLink()
                                }
                        }
                        .padding(AppTheme.spacingM)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                .stroke(isEmailFocused ? AppTheme.accent : AppTheme.cardBorder, lineWidth: 1)
                        )
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

                    // Send reset link button
                    Button {
                        sendResetLink()
                    } label: {
                        HStack(spacing: AppTheme.spacingS) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color(.systemBackground))
                                    .scaleEffect(0.8)
                            }
                            Text("Send Reset Link")
                                .font(.headline)
                        }
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingM)
                        .background(isFormValid ? AppTheme.accentGradient : LinearGradient(colors: [AppTheme.textTertiary], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                    }
                    .disabled(!isFormValid || isLoading)

                    // Back to sign in link
                    Button {
                        onBackToSignIn()
                    } label: {
                        Text("Back to Sign In")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        authService.isValidEmail(email)
    }

    // MARK: - Actions

    private func sendResetLink() {
        guard isFormValid else { return }

        errorMessage = nil
        isLoading = true
        isEmailFocused = false

        Task {
            do {
                try await authService.resetPassword(email: email)
                await MainActor.run {
                    isLoading = false
                    emailSent = true
                }
            } catch let error as AuthError {
                await MainActor.run {
                    errorMessage = error.errorDescription
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

// MARK: - Previews

#Preview("Form") {
    VStack {
        ForgotPasswordFormView(onBackToSignIn: {})
            .padding()
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}

#Preview("Success") {
    VStack {
        ForgotPasswordFormView(onBackToSignIn: {})
            .padding()
            .onAppear {
                // Simulate success state
            }
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}
