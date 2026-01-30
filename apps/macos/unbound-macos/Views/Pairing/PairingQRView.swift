//
//  PairingQRView.swift
//  unbound-macos
//
//  Pairing QR view - placeholder for daemon mode.
//  Device pairing is now handled by the daemon.
//

import SwiftUI

struct PairingQRView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            // QR placeholder
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.muted)
                .frame(width: 200, height: 200)
                .overlay(
                    Image(systemName: "qrcode")
                        .font(.system(size: 64))
                        .foregroundStyle(colors.mutedForeground)
                )

            Text("QR Pairing")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Device pairing is managed by the Unbound daemon.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
}

#Preview {
    PairingQRView()
        .frame(width: 300, height: 400)
}
