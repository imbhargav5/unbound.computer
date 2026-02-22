//
//  InitializationErrorView.swift
//  unbound-macos
//
//  Error view shown when app initialization fails
//

import SwiftUI

struct InitializationErrorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let error: Error
    let onRetry: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: IconSize.xxxxxxl))
                .foregroundStyle(colors.destructive)

            Text("Failed to Start")
                .font(Typography.title)
                .foregroundStyle(colors.foreground)

            VStack(spacing: Spacing.sm) {
                Text("Unbound encountered an error during startup:")
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)

                Text(error.localizedDescription)
                    .font(Typography.body)
                    .foregroundStyle(colors.foreground)
                    .padding(Spacing.lg)
                    .background(colors.muted.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .frame(maxWidth: 400)
            }

            HStack(spacing: Spacing.lg) {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}

#if DEBUG

#Preview {
    InitializationErrorView(
        error: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database migration failed"]),
        onRetry: {}
    )
}

#endif
