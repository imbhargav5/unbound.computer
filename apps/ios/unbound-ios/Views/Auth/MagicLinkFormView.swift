//
//  MagicLinkFormView.swift
//  unbound-ios
//
//  Passwordless authentication form using magic links.
//

import SwiftUI

struct MagicLinkFormView: View {
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
                    Image(systemName: "envelope.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(AppTheme.accent)

                    VStack(spacing: AppTheme.spacingS) {
                        Text("Check Your Email")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("We've sent a magic link to:")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        Text(email)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.accent)

                        Text("Click the link in your email to sign in. The link will expire in 1 hour.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, AppTheme.spacingXS)
                    }

                    VStack(spacing: AppTheme.spacingS) {
                        Button {
                            // Reset to send another email
                            emailSent = false
                            errorMessage = nil
                        } label: {
                            Text("Send Another Link")
                                .font(.headline)
                                .foregroundStyle(Color(.systemBackground))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.spacingM)
                                .background(AppTheme.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                        }

                        Button {
                            onBackToSignIn()
                        } label: {
                            Text("Back to Sign In")
                                .font(.body)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            } else {
                // Form state
                VStack(spacing: AppTheme.spacingM) {
                    // Header
                    VStack(spacing: AppTheme.spacingS) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(AppTheme.accent)

                        Text("Sign In with Magic Link")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Enter your email and we'll send you a magic link to sign in instantly—no password needed.")
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
                                    sendMagicLink()
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

                    // Send magic link button
                    Button {
                        sendMagicLink()
                    } label: {
                        HStack(spacing: AppTheme.spacingS) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color(.systemBackground))
                                    .scaleEffect(0.8)
                            }
                            Text("Send Magic Link")
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
                        Text("Sign in with password instead")
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

    private func sendMagicLink() {
        guard isFormValid else { return }

        errorMessage = nil
        isLoading = true
        isEmailFocused = false

        Task {
            do {
                try await authService.signInWithMagicLink(email: email)
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
        MagicLinkFormView(onBackToSignIn: {})
            .padding()
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}

#Preview("Success") {
    VStack {
        MagicLinkFormView(onBackToSignIn: {})
            .padding()
            .onAppear {
                // Simulate success state
            }
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}
