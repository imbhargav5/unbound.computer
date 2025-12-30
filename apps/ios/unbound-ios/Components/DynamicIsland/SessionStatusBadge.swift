import SwiftUI

struct SessionStatusBadge: View {
    let status: ActiveSession.SessionStatus
    let progress: Double

    @State private var isPulsing = false
    @State private var showCheckmark = false

    var body: some View {
        HStack(spacing: 6) {
            // Icon with animation
            Image(systemName: status.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(status.color)
                .opacity(isPulsing ? 0.6 : 1.0)
                .scaleEffect(showCheckmark ? 1.2 : 1.0)

            // Label
            Text(status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)

            // Progress for generating
            if status == .generating {
                Text("\(Int(progress * 100))%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(status.color.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
        .onAppear {
            startAnimations()
        }
        .onChange(of: status) { oldValue, newValue in
            if newValue == .merged || newValue == .ready {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    showCheckmark = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCheckmark = false
                    }
                }
            }
            startAnimations()
        }
    }

    private func startAnimations() {
        if status.isActive {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            isPulsing = false
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(ActiveSession.SessionStatus.allCases, id: \.self) { status in
            SessionStatusBadge(status: status, progress: status == .generating ? 0.65 : 1.0)
        }
    }
    .padding()
}
