//
//  WorkspaceNavbarTab.swift
//  unbound-macos
//
//  Shared tab chrome for the workspace navbar.
//

import SwiftUI

struct WorkspaceNavbarTab: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    var badge: String? = nil
    let isSelected: Bool
    let isClosable: Bool
    var showsTrailingDivider: Bool = false
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isCloseHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: ChatHeaderTokens.tabContentSpacing) {
                Text(label)
                    .font(GeistFont.sans(size: ChatHeaderTokens.tabFontSize, weight: ChatHeaderTokens.tabFontWeight))
                    .foregroundStyle(isSelected ? colors.sidebarText : colors.sidebarMeta)
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(GeistFont.sans(size: ChatHeaderTokens.badgeFontSize, weight: ChatHeaderTokens.badgeFontWeight))
                        .foregroundStyle(colors.accentAmber)
                        .padding(.horizontal, ChatHeaderTokens.badgeHorizontalPadding)
                        .padding(.vertical, ChatHeaderTokens.badgeVerticalPadding)
                        .background(colors.accentAmberMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: ChatHeaderTokens.badgeCornerRadius)
                                .stroke(colors.accentAmberBorder, lineWidth: BorderWidth.default)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: ChatHeaderTokens.badgeCornerRadius))
                }

                if isClosable {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: ChatHeaderTokens.closeIconSize, weight: .regular))
                            .foregroundStyle(isCloseHovered ? colors.sidebarText : colors.sidebarMeta)
                            .frame(width: ChatHeaderTokens.closeIconFrameSize, height: ChatHeaderTokens.closeIconFrameSize)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                }
            }
            .padding(.horizontal, ChatHeaderTokens.tabHorizontalPadding)
            .frame(height: LayoutMetrics.compactToolbarHeight)
            .background(isSelected ? colors.surface1 : colors.card)
            .overlay(alignment: .trailing) {
                if showsTrailingDivider {
                    Rectangle()
                        .fill(colors.border)
                        .frame(width: ChatHeaderTokens.tabSeparatorWidth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
