//
//  LoadingView.swift
//  unbound-ios
//
//  Loading view shown while checking authentication state.
//

import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AppTheme.spacingL) {
            // Animated logo
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: 80, height: 80)

                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(.systemBackground))
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
            }

            // Loading text
            VStack(spacing: AppTheme.spacingXS) {
                Text("Unbound")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: AppTheme.spacingS) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.accent)
                        .scaleEffect(0.8)

                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundPrimary)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Previews

#Preview {
    LoadingView()
}
