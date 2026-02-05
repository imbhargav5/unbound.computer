//
//  LoadingView.swift
//  unbound-macos
//
//  Loading view shown while checking session state.
//

import SwiftUI

struct LoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ZStack {
            colors.background

            VStack(spacing: Spacing.xl) {
                // Logo
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(colors.borderSecondary, lineWidth: 1)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(colors.foreground)
                    )

                // Loading indicator
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(colors.mutedForeground)

                Text("Loading...")
                    .font(Typography.caption)
                    .foregroundStyle(colors.inactive)
            }
        }
    }
}

#Preview {
    LoadingView()
        .frame(width: 400, height: 300)
}
