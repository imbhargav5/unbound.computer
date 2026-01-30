//
//  TabComponents.swift
//  unbound-macos
//
//  Shadcn-styled tab components
//

import SwiftUI

// MARK: - Segmented Tab Picker

struct SegmentedTabPicker<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selection: T
    let options: [T]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(option.rawValue)
                        .font(Typography.bodySmall)
                        .foregroundStyle(selection.id == option.id ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            selection.id == option.id ?
                            colors.card :
                            Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xs)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}
