//
//  PairingQRView.swift
//  unbound-macos
//
//  Displays a QR code for iOS device to scan and establish trust.
//

import SwiftUI

/// Pairing state
enum PairingState: Equatable {
    case generating
    case ready(NSImage)
    case waitingForScan
    case paired(TrustedDevice)
    case error(String)

    static func == (lhs: PairingState, rhs: PairingState) -> Bool {
        switch (lhs, rhs) {
        case (.generating, .generating),
             (.waitingForScan, .waitingForScan):
            return true
        case (.ready, .ready):
            return true
        case (.paired(let a), .paired(let b)):
            return a.deviceId == b.deviceId
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct PairingQRView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pairingState: PairingState = .generating
    @State private var expirationTimer: Timer?
    @State private var timeRemaining: Int = 300  // 5 minutes

    private let deviceIdentityService = DeviceIdentityService.shared

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Pair with iPhone")
                    .font(.title2.bold())

                Text("Scan this QR code with the Unbound app on your iPhone to establish a secure connection.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // QR Code or state view
            Group {
                switch pairingState {
                case .generating:
                    ProgressView("Generating QR Code...")
                        .frame(width: 300, height: 300)

                case .ready(let image):
                    qrCodeView(image)

                case .waitingForScan:
                    waitingView

                case .paired(let device):
                    pairedView(device)

                case .error(let message):
                    errorView(message)
                }
            }
            .frame(minHeight: 350)

            // Footer
            HStack(spacing: 16) {
                if case .ready = pairingState {
                    Button("Regenerate") {
                        generateQRCode()
                    }
                }

                Button(pairingState == .paired(trustRoot: nil) ? "Done" : "Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
        }
        .padding(32)
        .frame(width: 450)
        .onAppear {
            generateQRCode()
        }
        .onDisappear {
            expirationTimer?.invalidate()
        }
    }

    // MARK: - Views

    private func qrCodeView(_ image: NSImage) -> some View {
        VStack(spacing: 16) {
            // QR Code
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 250, height: 250)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(radius: 4)

            // Timer
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("Expires in \(formatTime(timeRemaining))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Device info
            VStack(spacing: 4) {
                Text(deviceIdentityService.deviceName)
                    .font(.headline)

                if let deviceId = deviceIdentityService.deviceId {
                    Text("ID: \(String(deviceId.uuidString.prefix(8)))...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var waitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Waiting for iPhone...")
                .font(.headline)

            Text("Approve the pairing request on your iPhone")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func pairedView(_ device: TrustedDevice) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Successfully Paired!")
                .font(.title3.bold())

            VStack(spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text("Trust Root")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            Text("Your Mac is now connected to your iPhone. Claude sessions will be encrypted end-to-end.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Pairing Failed")
                .font(.title3.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                generateQRCode()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func generateQRCode() {
        pairingState = .generating

        Task {
            do {
                let image = try deviceIdentityService.generatePairingQRImage()
                timeRemaining = 300  // Reset timer

                await MainActor.run {
                    pairingState = .ready(image)
                    startExpirationTimer()
                }
            } catch {
                await MainActor.run {
                    pairingState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func startExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            timeRemaining -= 1
            if timeRemaining <= 0 {
                expirationTimer?.invalidate()
                pairingState = .error("QR code expired. Please regenerate.")
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // Helper for pattern matching
    private func paired(trustRoot: TrustedDevice?) -> PairingState {
        if let trustRoot {
            return .paired(trustRoot)
        }
        return .generating
    }
}

// MARK: - Preview

#Preview {
    PairingQRView()
}
