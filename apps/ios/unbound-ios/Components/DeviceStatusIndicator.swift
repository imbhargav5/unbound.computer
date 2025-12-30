import SwiftUI

struct DeviceStatusIndicator: View {
    let status: Device.DeviceStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.displayName)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .online:
            return AppTheme.statusOnline
        case .offline:
            return AppTheme.statusOffline
        case .busy:
            return AppTheme.statusBusy
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DeviceStatusIndicator(status: .online)
        DeviceStatusIndicator(status: .offline)
        DeviceStatusIndicator(status: .busy)
    }
    .padding()
}
