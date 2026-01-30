import SwiftUI

enum AuthState {
    case idle
    case initializing
    case waitingForScan
    case authorizing
    case authorized
    case failed(Error)
}

struct AuthenticationView: View {
    @EnvironmentObject private var authService: AuthenticationService

    @State private var authState: AuthState = .idle
    @State private var qrCodeURL: String?
    @State private var sessionId: String?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Sign In")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Scan QR code with your trusted device")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)

            // QR Code or loading state
            Group {
                switch authState {
                case .idle:
                    startButton

                case .initializing:
                    loadingView(message: "Initializing session...")

                case .waitingForScan:
                    if let qrCodeURL {
                        qrCodeView(url: qrCodeURL)
                    }

                case .authorizing:
                    loadingView(message: "Authorizing...")

                case .authorized:
                    successView

                case .failed(let error):
                    errorView(error: error)
                }
            }
            .frame(maxHeight: .infinity)

            Spacer()
        }
        .padding()
    }

    // MARK: - Subviews

    private var startButton: some View {
        Button(action: { Task { await startAuthFlow() } }) {
            Text("Generate QR Code")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    private func loadingView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .foregroundColor(.secondary)
        }
    }

    private func qrCodeView(url: String) -> some View {
        VStack(spacing: 16) {
            // QR Code placeholder
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 250, height: 250)

                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 250, height: 250)

                case .failure:
                    Image(systemName: "qrcode")
                        .font(.system(size: 100))
                        .foregroundColor(.gray)
                        .frame(width: 250, height: 250)

                @unknown default:
                    EmptyView()
                }
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(radius: 4)

            Text("Scan with your trusted device")
                .font(.callout)
                .foregroundColor(.secondary)

            Text("Waiting for authorization...")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { authState = .idle }) {
                Text("Cancel")
                    .font(.callout)
                    .foregroundColor(.red)
            }
            .padding(.top, 8)
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Authorized!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Loading sessions...")
                .foregroundColor(.secondary)
        }
    }

    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Authentication Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { authState = .idle }) {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Auth Flow

    private func startAuthFlow() async {
        authState = .initializing

        do {
            // Step 1: Initialize web session
            let sessionInit = try await authService.initWebSession()

            sessionId = sessionInit.sessionId
            qrCodeURL = sessionInit.qrCodeUrl

            authState = .waitingForScan

            // Step 2: Wait for authorization
            authState = .authorizing

            try await authService.waitForAuthorization(sessionId: sessionInit.sessionId)

            authState = .authorized

        } catch {
            authState = .failed(error)
            Config.log("❌ Auth flow failed: \(error)")
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationService.shared)
}
