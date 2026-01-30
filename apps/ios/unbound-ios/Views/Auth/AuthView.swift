//
//  AuthView.swift
//  unbound-ios
//
//  Main authentication view that switches between sign in and sign up forms.
//

import SwiftUI

enum AuthMode: Equatable {
    case signIn
    case signUp
    case magicLink
    case forgotPassword
}

struct AuthView: View {
    @Environment(AuthService.self) private var authService
    @State private var authMode: AuthMode = .signIn

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingXL) {
                // Show logo and header only for main modes
                if authMode == .signIn || authMode == .signUp {
                    headerSection
                }

                // Auth mode picker (only for sign in/up)
                if authMode == .signIn || authMode == .signUp {
                    authModePicker
                }

                // Form content
                Group {
                    switch authMode {
                    case .signIn:
                        SignInFormView(
                            onForgotPassword: {
                                withAnimation {
                                    authMode = .forgotPassword
                                }
                            },
                            onMagicLink: {
                                withAnimation {
                                    authMode = .magicLink
                                }
                            }
                        )
                    case .signUp:
                        SignUpFormView()
                    case .magicLink:
                        MagicLinkFormView(onBackToSignIn: {
                            withAnimation {
                                authMode = .signIn
                            }
                        })
                    case .forgotPassword:
                        ForgotPasswordFormView(onBackToSignIn: {
                            withAnimation {
                                authMode = .signIn
                            }
                        })
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                // Divider and OAuth buttons (only for sign in/up)
                if authMode == .signIn || authMode == .signUp {
                    dividerSection
                    OAuthButtonsView()
                }

                Spacer(minLength: AppTheme.spacingXL)
            }
            .padding(AppTheme.spacingM)
        }
        .background(AppTheme.backgroundPrimary)
        .animation(.easeInOut(duration: 0.2), value: authMode)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppTheme.spacingM) {
            // App icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: 80, height: 80)

                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(.systemBackground))
            }
            .padding(.top, AppTheme.spacingXL)

            VStack(spacing: AppTheme.spacingXS) {
                Text("Unbound")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Secure Claude Code companion")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    // MARK: - Auth Mode Picker

    private var authModePicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    authMode = .signIn
                }
            } label: {
                Text("Sign In")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(authMode == .signIn ? Color(.systemBackground) : AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingS)
                    .background(
                        authMode == .signIn
                            ? AppTheme.accentGradient
                            : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    authMode = .signUp
                }
            } label: {
                Text("Sign Up")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(authMode == .signUp ? Color(.systemBackground) : AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingS)
                    .background(
                        authMode == .signUp
                            ? AppTheme.accentGradient
                            : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Divider Section

    private var dividerSection: some View {
        HStack(spacing: AppTheme.spacingM) {
            Rectangle()
                .fill(AppTheme.cardBorder)
                .frame(height: 1)

            Text("or continue with")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)

            Rectangle()
                .fill(AppTheme.cardBorder)
                .frame(height: 1)
        }
        .padding(.vertical, AppTheme.spacingS)
    }
}

// MARK: - Previews

#Preview {
    AuthView()
        .environment(AuthService.shared)
}
