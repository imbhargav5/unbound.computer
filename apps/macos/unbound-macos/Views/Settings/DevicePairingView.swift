//
//  DevicePairingView.swift
//  unbound-macos
//
//  Device pairing view - placeholder for daemon mode.
//  Device pairing is now handled by the daemon.
//

import SwiftUI

struct DevicePairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // Icon
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(colors.mutedForeground)

            // Title
            Text("Device Pairing")
                .font(Typography.h2)
                .foregroundStyle(colors.foreground)

            // Description
            Text("Device pairing is managed by the Unbound daemon. Use the CLI or daemon settings to pair devices.")
                .font(Typography.body)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()

            // Dismiss button
            Button("Close") {
                dismiss()
            }
            .buttonPrimary(size: .md)
        }
        .padding(Spacing.xxl)
        .frame(width: 500, height: 400)
        .background(colors.background)
    }
}

#Preview {
    DevicePairingView()
        .frame(width: 500, height: 400)
}
