import SwiftUI

struct DevicePickerHeader: View {
    let device: SyncedDevice?
    @Binding var showDevicePicker: Bool

    var body: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            showDevicePicker = true
        } label: {
            HStack(spacing: AppTheme.spacingS) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                // Device name
                Text(deviceLabel)
                    .font(Typography.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingS)
        }
        .buttonStyle(.plain)
    }

    private var deviceLabel: String {
        guard let device else { return "No Devices" }
        return device.hostname ?? device.name
    }

    private var statusColor: Color {
        guard let device else { return .gray }
        switch device.status {
        case .online: return .green
        case .offline: return .gray
        case .busy: return .orange
        }
    }
}
