//
//  SignInFormView.swift
//  unbound-ios
//
//  Email/password sign in form.
//

import SwiftUI

struct SignInFormView: View {
    @Environment(AuthService.self) private var authService

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    var onForgotPassword: (() -> Void)?
    var onMagicLink: (() -> Void)?

    enum Field: Hashable {
        case email
        case password
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
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        signIn()
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

            // Forgot password and magic link options
            HStack {
                if let onMagicLink {
                    Button {
                        onMagicLink()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text("Use magic link")
                                .font(.caption)
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }

                Spacer()

                if let onForgotPassword {
                    Button {
                        onForgotPassword()
                    } label: {
                        Text("Forgot password?")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            // Sign in button
            Button {
                signIn()
            } label: {
                HStack(spacing: AppTheme.spacingS) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color(.systemBackground))
                            .scaleEffect(0.8)
                    }
                    Text("Sign In")
                        .font(.headline)
                }
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingM)
                .background(isFormValid ? AppTheme.accentGradient : LinearGradient(colors: [AppTheme.textTertiary], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            }
            .disabled(!isFormValid || isLoading)
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && !password.isEmpty
    }

    // MARK: - Actions

    private func signIn() {
        guard isFormValid else { return }

        errorMessage = nil
        isLoading = true
        focusedField = nil

        Task {
            do {
                try await authService.signInWithEmail(email: email, password: password)
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

#Preview {
    VStack {
        SignInFormView()
            .padding()
    }
    .background(AppTheme.backgroundPrimary)
    .environment(AuthService.shared)
}
