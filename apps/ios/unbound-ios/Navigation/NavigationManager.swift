import SwiftUI

// MARK: - Navigation Routes

enum AppRoute: Hashable {
    case deviceDetail(Device)
    case syncedDeviceDetail(SyncedDevice)
    case syncedSessionDetail(SyncedSession)
    case projectDetail(Device, Project)
    case chat(Chat)
    case newChat(Project)
    case accountSettings
}

// MARK: - Navigation Manager

@Observable
class NavigationManager {
    var path = NavigationPath()

    func navigateToDevice(_ device: Device) {
        path.append(AppRoute.deviceDetail(device))
    }

    func navigateToSyncedDevice(_ device: SyncedDevice) {
        path.append(AppRoute.syncedDeviceDetail(device))
    }

    func navigateToSyncedSession(_ session: SyncedSession) {
        path.append(AppRoute.syncedSessionDetail(session))
    }

    func navigateToProject(_ project: Project, on device: Device) {
        path.append(AppRoute.projectDetail(device, project))
    }

    func navigateToChat(_ chat: Chat) {
        path.append(AppRoute.chat(chat))
    }

    func navigateToNewChat(in project: Project) {
        path.append(AppRoute.newChat(project))
    }

    func navigateToAccountSettings() {
        path.append(AppRoute.accountSettings)
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    func popToRoot() {
        path = NavigationPath()
    }
}

// MARK: - Environment Key

private struct NavigationManagerKey: EnvironmentKey {
    static let defaultValue = NavigationManager()
}

extension EnvironmentValues {
    var navigationManager: NavigationManager {
        get { self[NavigationManagerKey.self] }
        set { self[NavigationManagerKey.self] = newValue }
    }
}
