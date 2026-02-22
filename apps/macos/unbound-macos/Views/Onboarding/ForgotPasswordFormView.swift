//
//  ForgotPasswordFormView.swift
//  unbound-macos
//
//  Password reset email input form.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.auth")

struct ForgotPasswordFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @FocusState private var isFocused: Bool

    var onSuccess: (String) -> Void

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

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(colors.destructive)
            }

            // Send button
            Button {
                sendResetEmail()
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(.circular)
                    }
                    Text(isLoading ? "Sending..." : "Send reset link")
                        .font(Typography.label)
                    Spacer()
                    Image(systemName: "paperplane")
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
            .disabled(isLoading || email.isEmpty)
            .opacity(email.isEmpty ? 0.5 : 1)
        }
    }

    private var emailField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "envelope")
                .font(.system(size: IconSize.md))
                .foregroundStyle(isFocused ? colors.sidebarText : colors.inactive)

            TextField("you@example.com", text: $email)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(colors.foreground)
                .focused($isFocused)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .onSubmit {
                    if !email.isEmpty {
                        sendResetEmail()
                    }
                }
        }
        .frame(height: 44)
        .padding(.horizontal, Spacing.md)
        .background(colors.surface2.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    isFocused ? colors.borderSecondary : colors.border,
                    lineWidth: 1
                )
        )
    }

    private func sendResetEmail() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                // Use daemon for password reset (magic link)
                try await appState.loginWithProvider("reset_password", email: email)
                onSuccess(email)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#if DEBUG

#Preview {
    ForgotPasswordFormView { email in
        logger.info("Reset link sent to: \(email)")
    }
    .environment(AppState())
    .padding(Spacing.xxxxl)
    .background(ThemeColors(.dark).background)
    .frame(width: 400)
}

#endif
