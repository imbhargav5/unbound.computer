//
//  LoadingView.swift
//  unbound-macos
//
//  Loading view shown while checking session state.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: Spacing.xl) {
                // Logo
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    )

                // Loading indicator
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(.white.opacity(0.5))

                Text("Loading...")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

#Preview {
    LoadingView()
        .frame(width: 400, height: 300)
}
