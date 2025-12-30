import SwiftUI

struct DynamicIslandButton: View {
    let activeCount: Int
    let hasGenerating: Bool
    let action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                // Animated dot
                Circle()
                    .fill(hasGenerating ? AppTheme.accent : .green)
                    .frame(width: 8, height: 8)
                    .opacity(isPulsing && hasGenerating ? 0.5 : 1.0)

                Text("\(activeCount) Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        hasGenerating
                            ? AppTheme.accent.opacity(0.5)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if hasGenerating {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: hasGenerating) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DynamicIslandButton(activeCount: 3, hasGenerating: true) {}
        DynamicIslandButton(activeCount: 2, hasGenerating: false) {}
        DynamicIslandButton(activeCount: 0, hasGenerating: false) {}
    }
    .padding()
}
