import SwiftUI

struct ClaudeAvatarView: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.claudeGradient)

            Image(systemName: "brain.head.profile")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        ClaudeAvatarView(size: 24)
        ClaudeAvatarView(size: 32)
        ClaudeAvatarView(size: 48)
    }
    .padding()
}
