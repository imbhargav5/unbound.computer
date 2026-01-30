//
//  DevicePairingView.swift
//  unbound-ios
//
//  View for pairing with a new device (Mac) by scanning its QR code.
//  Simplified token-based pairing flow with Supabase.
//

import SwiftUI

/// View state for the pairing flow
enum PairingState: Equatable {
    case scanning
    case scanned(PairingQRPayload)
    case pairing
    case success(String)  // Device name
    case error(String)

    static func == (lhs: PairingState, rhs: PairingState) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning),
             (.pairing, .pairing):
            return true
        case (.scanned(let a), .scanned(let b)):
            return a.tokenId == b.tokenId
        case (.success(let a), .success(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct DevicePairingView: View {
    @Environment(\.dismiss) private var dismiss

    // Access singleton directly - don't wrap in @State
    private var pairingService: PairingService { PairingService.shared }

    @State private var pairingState: PairingState = .scanning
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary
                    .ignoresSafeArea()

                switch pairingState {
                case .scanning:
                    scanningView

                case .scanned(let qrPayload):
                    devicePreviewView(qrPayload)

                case .pairing:
                    pairingProgressView

                case .success(let deviceName):
                    successView(deviceName)

                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    showScanner = false
                    handleScannedCode(code)
                }
            }
        }
    }

    // MARK: - View States

    private var scanningView: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(AppTheme.accent)

            VStack(spacing: AppTheme.spacingM) {
                Text("Pair a New Device")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Scan the QR code displayed on your Mac to approve and pair it with your account.")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingL)
            }

            Spacer()

            VStack(spacing: AppTheme.spacingM) {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingM)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Text("Your Mac will show a QR code in Settings → Devices")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
    }

    private func devicePreviewView(_ payload: PairingQRPayload) -> some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            // Device icon
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "laptopcomputer")
                    .font(.system(size: 50))
                    .foregroundStyle(AppTheme.accent)
            }

            // Device info
            VStack(spacing: AppTheme.spacingM) {
                Text(payload.deviceName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "shield.checkmark.fill")
                        .foregroundStyle(.green)
                    Text("Requesting Approval")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .font(.subheadline)

                Text("Token: \(payload.token)")
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.textTertiary)
            }

            // Trust info
            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                trustInfoRow(icon: "lock.shield", text: "End-to-end encrypted sessions")
                trustInfoRow(icon: "key", text: "Secure session key sharing")
                trustInfoRow(icon: "eye.slash", text: "Only you can read messages")
            }
            .padding()
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(12)
            .padding(.horizontal, AppTheme.spacingL)

            Spacer()

            // Actions
            VStack(spacing: AppTheme.spacingM) {
                Button {
                    approveDevice(payload)
                } label: {
                    Label("Approve Device", systemImage: "checkmark.shield")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingM)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    pairingState = .scanning
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingM)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
    }

    private var pairingProgressView: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AppTheme.accent, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: true)

                Image(systemName: "checkmark.shield")
                    .font(.title)
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: AppTheme.spacingS) {
                Text("Approving Device")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Setting verified status on device...")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacingL)

            Spacer()
        }
    }

    private func successView(_ deviceName: String) -> some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
            }

            VStack(spacing: AppTheme.spacingM) {
                Text("Device Approved!")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("\(deviceName) has been approved and can now connect to your account.")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingL)
            }

            // Device card
            HStack(spacing: AppTheme.spacingM) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Trusted Executor")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding()
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(12)
            .padding(.horizontal, AppTheme.spacingL)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingM)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.red.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
            }

            VStack(spacing: AppTheme.spacingM) {
                Text("Pairing Failed")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingL)
            }

            Spacer()

            VStack(spacing: AppTheme.spacingM) {
                Button {
                    pairingState = .scanning
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingM)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
    }

    // MARK: - Helpers

    private func trustInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: AppTheme.spacingS) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        do {
            let qrPayload = try PairingQRPayload.fromJSON(code)

            // Check if expired
            if qrPayload.isExpired {
                pairingState = .error("This QR code has expired. Please generate a new one on your Mac.")
                return
            }

            // Check version
            if qrPayload.version != 2 {
                pairingState = .error("Incompatible QR code version. Please update your app.")
                return
            }

            pairingState = .scanned(qrPayload)

        } catch {
            pairingState = .error("Invalid QR code. Please scan a valid pairing code.")
        }
    }

    private func approveDevice(_ payload: PairingQRPayload) {
        pairingState = .pairing

        Task {
            do {
                try await pairingService.approvePairing(payload: payload)

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

                await MainActor.run {
                    pairingState = .success(payload.deviceName)
                }

            } catch {
                await MainActor.run {
                    pairingState = .error(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DevicePairingView()
}
