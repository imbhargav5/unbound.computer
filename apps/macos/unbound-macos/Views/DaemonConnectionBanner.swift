//
//  DaemonConnectionBanner.swift
//  unbound-macos
//
//  Banner shown when daemon connection is lost or unavailable.
//  Provides retry functionality and connection status feedback.
//

import SwiftUI

struct DaemonConnectionBanner: View {
    let state: DaemonConnectionState
    let onRetry: () -> Void

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .font(.system(size: 14, weight: .medium))

            // Status message
            Text(statusMessage)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            // Retry button
            if canRetry {
                Button(action: {
                    isRetrying = true
                    onRetry()
                    // Reset after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        isRetrying = false
                    }
                }) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(isRetrying ? "Connecting..." : "Retry")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isRetrying)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .disconnected:
            Image(systemName: "wifi.slash")
        case .connecting:
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 16, height: 16)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var statusMessage: String {
        switch state {
        case .disconnected:
            return "Disconnected from daemon"
        case .connecting:
            return "Connecting to daemon..."
        case .connected:
            return "Connected"
        case .failed(let reason):
            return "Connection failed: \(reason)"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .disconnected:
            return Color.orange.opacity(0.9)
        case .connecting:
            return Color.blue.opacity(0.9)
        case .connected:
            return Color.green.opacity(0.9)
        case .failed:
            return Color.red.opacity(0.9)
        }
    }

    private var canRetry: Bool {
        switch state {
        case .disconnected, .failed:
            return true
        case .connecting, .connected:
            return false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DaemonConnectionBanner(state: .disconnected, onRetry: {})
        DaemonConnectionBanner(state: .connecting, onRetry: {})
        DaemonConnectionBanner(state: .failed("Daemon not responding"), onRetry: {})
    }
    .padding()
    .frame(width: 600)
}
