import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCodeScanned: (String) -> Void

    @State private var cameraPermission: CameraPermission = .unknown
    @State private var isScanning = true
    @State private var lastScannedCode: String?
    @State private var showFlash = false
    @State private var torchOn = false

    enum CameraPermission {
        case unknown
        case authorized
        case denied
        case restricted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview or placeholder
                if cameraPermission == .authorized {
                    QRCameraPreview(
                        isScanning: $isScanning,
                        torchOn: $torchOn,
                        onCodeDetected: handleCodeDetected
                    )
                    .ignoresSafeArea()
                } else {
                    AppTheme.backgroundPrimary
                        .ignoresSafeArea()
                }

                // Overlay
                VStack(spacing: 0) {
                    // Top overlay
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(height: 120)

                    // Scanner area
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(.black.opacity(0.6))

                        // Viewfinder
                        ZStack {
                            // Transparent center
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.clear)
                                .frame(width: 250, height: 250)

                            // Corner brackets
                            ViewfinderCorners()
                                .frame(width: 250, height: 250)

                            // Scanning line animation
                            if isScanning && cameraPermission == .authorized {
                                ScanningLine()
                            }
                        }
                        .frame(width: 250, height: 250)

                        Rectangle()
                            .fill(.black.opacity(0.6))
                    }
                    .frame(height: 250)

                    // Bottom overlay with instructions
                    ZStack {
                        Rectangle()
                            .fill(.black.opacity(0.6))

                        VStack(spacing: AppTheme.spacingL) {
                            // Instructions
                            VStack(spacing: AppTheme.spacingS) {
                                Text("Scan QR Code")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)

                                Text("Point your camera at the QR code displayed on your computer running Claude Code")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, AppTheme.spacingL)
                            }

                            // Controls
                            if cameraPermission == .authorized {
                                HStack(spacing: AppTheme.spacingXL) {
                                    // Torch button
                                    Button {
                                        toggleTorch()
                                    } label: {
                                        VStack(spacing: AppTheme.spacingXS) {
                                            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                                .font(.title2)
                                            Text("Light")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(torchOn ? .yellow : .white.opacity(0.7))
                                    }

                                    // Demo scan button (for testing)
                                    Button {
                                        simulateScan()
                                    } label: {
                                        VStack(spacing: AppTheme.spacingXS) {
                                            Image(systemName: "qrcode")
                                                .font(.title2)
                                            Text("Demo")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                            }

                            // Permission denied state
                            if cameraPermission == .denied {
                                VStack(spacing: AppTheme.spacingM) {
                                    Image(systemName: "camera.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.white)

                                    Text("Camera Access Required")
                                        .font(.headline)
                                        .foregroundStyle(.white)

                                    Text("Please enable camera access in Settings to scan QR codes.")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)

                                    Button("Open Settings") {
                                        openSettings()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.white)
                                }
                                .padding(AppTheme.spacingL)
                            }
                        }
                        .padding(.top, AppTheme.spacingXL)
                    }
                }

                // Flash overlay
                if showFlash {
                    Color.white
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                checkCameraPermission()
            }
        }
    }

    // MARK: - Actions

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        case .denied:
            cameraPermission = .denied
        case .restricted:
            cameraPermission = .restricted
        @unknown default:
            cameraPermission = .denied
        }
    }

    private func handleCodeDetected(_ code: String) {
        guard isScanning, lastScannedCode != code else { return }

        isScanning = false
        lastScannedCode = code

        // Flash effect
        withAnimation(.easeOut(duration: 0.1)) {
            showFlash = true
        }

        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.2)) {
                showFlash = false
            }
        }

        // Return result after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onCodeScanned(code)
        }
    }

    private func toggleTorch() {
        torchOn.toggle()
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func simulateScan() {
        // For demo/testing purposes
        let fakeCode = "claude-code://connect?session=\(UUID().uuidString)&device=MacBook-Pro"
        handleCodeDetected(fakeCode)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Camera Preview

struct QRCameraPreview: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var torchOn: Bool
    let onCodeDetected: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.onCodeDetected = onCodeDetected
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.setTorch(torchOn)
        if isScanning {
            uiView.startScanning()
        } else {
            uiView.stopScanning()
        }
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.cleanup()
    }
}

class CameraPreviewView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeDetected: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        self.captureSession = session
        self.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func startScanning() {
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
            }
        }
    }

    func stopScanning() {
        if captureSession?.isRunning == true {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.stopRunning()
            }
        }
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }

        onCodeDetected?(stringValue)
    }

    func cleanup() {
        setTorch(false)
        captureSession?.stopRunning()
        captureSession = nil
        onCodeDetected = nil
    }

    deinit {
        cleanup()
    }
}

// MARK: - Viewfinder Corners

struct ViewfinderCorners: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cornerLength: CGFloat = 30
            let lineWidth: CGFloat = 4

            Path { path in
                // Top-left corner
                path.move(to: CGPoint(x: 0, y: cornerLength))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))

                // Top-right corner
                path.move(to: CGPoint(x: size.width - cornerLength, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: cornerLength))

                // Bottom-right corner
                path.move(to: CGPoint(x: size.width, y: size.height - cornerLength))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: size.width - cornerLength, y: size.height))

                // Bottom-left corner
                path.move(to: CGPoint(x: cornerLength, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height - cornerLength))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

// MARK: - Scanning Line

struct ScanningLine: View {
    @State private var offset: CGFloat = -100

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.8),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = 100
                }
            }
    }
}

// MARK: - Previews

#Preview {
    QRScannerView { code in
        print("Scanned: \(code)")
    }
}
