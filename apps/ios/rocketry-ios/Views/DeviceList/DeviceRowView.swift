import SwiftUI

struct DeviceRowView: View {
    let device: Device

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Device Icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: device.type.iconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            // Device Info
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(device.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(device.hostname)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.spacingS) {
                    DeviceStatusIndicator(status: device.status)

                    Text("\(device.projectCount) project\(device.projectCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .shadow(
            color: AppTheme.cardShadowColor,
            radius: AppTheme.cardShadowRadius,
            x: 0,
            y: AppTheme.cardShadowY
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }
}

#Preview {
    VStack(spacing: 16) {
        DeviceRowView(device: MockData.devices[0])
        DeviceRowView(device: MockData.devices[1])
        DeviceRowView(device: MockData.devices[2])
    }
    .padding()
    .background(Color(.systemBackground))
}
