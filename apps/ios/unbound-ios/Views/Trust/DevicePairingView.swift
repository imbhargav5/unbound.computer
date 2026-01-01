//
//  DevicePairingView.swift
//  unbound-ios
//
//  View for pairing with a new device (Mac) by scanning its QR code.
//  Part of the device-rooted trust architecture.
//

import SwiftUI

/// View state for the pairing flow
enum PairingState: Equatable {
    case scanning
    case scanned(PairingQRData)
    case confirming
    case pairing
    case success(TrustedDevice)
    case error(String)

    static func == (lhs: PairingState, rhs: PairingState) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning),
             (.confirming, .confirming),
             (.pairing, .pairing):
            return true
        case (.scanned(let a), .scanned(let b)):
            return a.deviceId == b.deviceId
        case (.success(let a), .success(let b)):
            return a.deviceId == b.deviceId
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct DevicePairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deviceTrustService) private var trustService

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

                case .scanned(let qrData):
                    devicePreviewView(qrData)

                case .confirming:
                    confirmingView

                case .pairing:
                    pairingProgressView

                case .success(let device):
                    successView(device)

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

                Text("Scan the QR code displayed on your Mac running Claude Code to establish a secure connection.")
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

                Text("Your Mac will display a QR code when you run 'unbound pair'")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
    }

    private func devicePreviewView(_ qrData: PairingQRData) -> some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            // Device icon
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: deviceIcon(for: qrData.role))
                    .font(.system(size: 50))
                    .foregroundStyle(AppTheme.accent)
            }

            // Device info
            VStack(spacing: AppTheme.spacingM) {
                Text(qrData.deviceName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "shield.checkmark.fill")
                        .foregroundStyle(.green)
                    Text(roleDisplayName(qrData.role))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .font(.subheadline)

                Text("Device ID: \(String(qrData.deviceId.prefix(8)))...")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            // Trust info
            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                trustInfoRow(icon: "lock.shield", text: "End-to-end encrypted connection")
                trustInfoRow(icon: "key", text: "Unique session keys per conversation")
                trustInfoRow(icon: "eye.slash", text: "Only you and this device can read messages")
            }
            .padding()
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(12)
            .padding(.horizontal, AppTheme.spacingL)

            Spacer()

            // Actions
            VStack(spacing: AppTheme.spacingM) {
                Button {
                    approveDevice(qrData)
                } label: {
                    Label("Trust This Device", systemImage: "checkmark.shield")
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

    private var confirmingView: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.accent)

            Text("Establishing Trust...")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()
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

                Image(systemName: "key.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: AppTheme.spacingS) {
                Text("Establishing Secure Connection")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Computing shared secrets and verifying device identity...")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacingL)

            Spacer()
        }
    }

    private func successView(_ device: TrustedDevice) -> some View {
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
                Text("Device Trusted!")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("\(device.name) has been added to your trusted devices.")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingL)
            }

            // Device card
            HStack(spacing: AppTheme.spacingM) {
                Image(systemName: deviceIcon(for: device.role))
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(roleDisplayName(device.role))
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

    private func deviceIcon(for role: DeviceRole) -> String {
        switch role {
        case .trustRoot:
            return "iphone"
        case .trustedExecutor:
            return "laptopcomputer"
        case .temporaryViewer:
            return "globe"
        }
    }

    private func roleDisplayName(_ role: DeviceRole) -> String {
        switch role {
        case .trustRoot:
            return "Trust Root"
        case .trustedExecutor:
            return "Trusted Executor"
        case .temporaryViewer:
            return "Temporary Viewer"
        }
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        do {
            let qrData = try PairingQRData.fromJSON(code)

            // Check if expired
            if qrData.isExpired {
                pairingState = .error("This QR code has expired. Please generate a new one on your Mac.")
                return
            }

            // Check version
            if qrData.version != 2 {
                pairingState = .error("Incompatible QR code version. Please update your CLI.")
                return
            }

            pairingState = .scanned(qrData)

        } catch {
            pairingState = .error("Invalid QR code. Please scan a valid pairing code from Claude Code.")
        }
    }

    private func approveDevice(_ qrData: PairingQRData) {
        pairingState = .pairing

        Task {
            do {
                let result = try trustService.processPairingQR(qrData)

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

                await MainActor.run {
                    pairingState = .success(result.trustedDevice)
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
