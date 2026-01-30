//
//  SplashView.swift
//  unbound-macos
//
//  Loading splash screen shown during app initialization
//

import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    let statusMessage: String
    let progress: Double

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // App icon or logo
            Image(systemName: "cube.fill")
                .font(.system(size: IconSize.xxxxxxl))
                .foregroundStyle(colors.primary)

            Text("Unbound")
                .font(Typography.title)
                .foregroundStyle(colors.foreground)

            VStack(spacing: Spacing.md) {
                // Progress bar
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(colors.primary)

                // Status message
                Text(statusMessage)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}

#Preview {
    SplashView(statusMessage: "Initializing database...", progress: 0.5)
}
