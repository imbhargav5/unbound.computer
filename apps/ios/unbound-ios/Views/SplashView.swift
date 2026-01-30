//
//  SplashView.swift
//  unbound-ios
//
//  Loading splash screen shown during app initialization
//

import SwiftUI

struct SplashView: View {
    let statusMessage: String
    let progress: Double

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon or logo
            Image(systemName: "cube.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accent)

            Text("Unbound")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 12) {
                // Progress bar
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(AppTheme.accent)

                // Status message
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundPrimary)
    }
}

#Preview {
    SplashView(statusMessage: "Initializing database...", progress: 0.5)
}
