//
//  TopNavbar.swift
//  unbound-macos
//
//  Top navigation bar replacing the empty titlebar gap.
//  Contains sidebar toggles, settings, and a draggable center area.
//

import SwiftUI

struct TopNavbar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let onOpenSettings: () -> Void

    /// Space needed for traffic lights (close, minimize, zoom)
    private let trafficLightWidth: CGFloat = 78

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left section: traffic light spacing + left sidebar toggle
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: trafficLightWidth)

                if !appState.localSettings.isZenModeEnabled {
                    IconButton(systemName: "sidebar.left", action: {
                        withAnimation(.easeOut(duration: Duration.fast)) {
                            appState.localSettings.leftSidebarVisible.toggle()
                        }
                    })
                }
            }

            // Center: draggable spacer for window movement
            ToolbarDraggableSpacer()

            // Right section: right sidebar toggle + settings
            HStack(spacing: Spacing.xxs) {
                if !appState.localSettings.isZenModeEnabled {
                    IconButton(systemName: "sidebar.right", action: {
                        withAnimation(.easeOut(duration: Duration.fast)) {
                            appState.localSettings.rightSidebarVisible.toggle()
                        }
                    })

                    IconButton(systemName: "gearshape", action: onOpenSettings)
                }
            }
            .padding(.trailing, Spacing.sm)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(colors.toolbarBackground)
        .background(WindowDragView())
        .overlay(alignment: .bottom) {
            ShadcnDivider()
        }
    }
}
