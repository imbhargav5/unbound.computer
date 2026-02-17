import SwiftUI

struct ClaudeMessageBubbleView: View {
    let message: Message
    var showRoleIcon: Bool = false

    var body: some View {
        MessageBubbleView(message: message, showRoleIcon: showRoleIcon)
    }
}
