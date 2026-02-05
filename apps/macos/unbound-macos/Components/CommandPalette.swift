//
//  CommandPalette.swift
//  unbound-macos
//
//  Command palette (Cmd+K) for quick actions and navigation
//

import SwiftUI

// MARK: - Command Item

struct CommandItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let shortcut: String?
    let action: () -> Void

    init(icon: String, title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }
}

// MARK: - Command Palette View

struct CommandPalette: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    let commands: [CommandItem]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var filteredCommands: [CommandItem] {
        if searchText.isEmpty {
            return commands
        }
        return commands.filter { command in
            command.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(colors.mutedForeground)

                TextField("Type a command or search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(colors.foreground)
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelectedCommand()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }

                // Escape hint
                Text("esc")
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(colors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            ShadcnDivider()

            // Commands list
            if filteredCommands.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: IconSize.xxl))
                        .foregroundStyle(colors.mutedForeground)

                    Text("No commands found")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                CommandRow(
                                    command: command,
                                    isSelected: index == selectedIndex,
                                    onSelect: {
                                        executeCommand(command)
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: Duration.fast)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 500)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .shadow(color: Color(hex: "0D0D0D").opacity(0.3), radius: 20, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.return) {
            executeSelectedCommand()
            return .handled
        }
    }

    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < filteredCommands.count {
            selectedIndex = newIndex
        }
    }

    private func executeSelectedCommand() {
        guard !filteredCommands.isEmpty,
              selectedIndex < filteredCommands.count else { return }
        executeCommand(filteredCommands[selectedIndex])
    }

    private func executeCommand(_ command: CommandItem) {
        isPresented = false
        command.action()
    }
}

// MARK: - Command Row

struct CommandRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let command: CommandItem
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Icon
                Image(systemName: command.icon)
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)
                    .frame(width: IconSize.xl)

                // Title
                Text(command.title)
                    .font(Typography.body)
                    .foregroundStyle(colors.foreground)

                Spacer()

                // Shortcut (if any)
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(colors.muted)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected || isHovered ? colors.accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.xs)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Command Palette Overlay

struct CommandPaletteOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    let commands: [CommandItem]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color(hex: "0D0D0D").opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Palette positioned near top
            VStack {
                Spacer()
                    .frame(height: 100)

                CommandPalette(
                    isPresented: $isPresented,
                    commands: commands
                )

                Spacer()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

#Preview {
    ZStack {
        Color(hex: "0D0D0D").opacity(0.8)
            .ignoresSafeArea()

        CommandPalette(
            isPresented: .constant(true),
            commands: [
                CommandItem(icon: "folder.badge.plus", title: "Add Repository", shortcut: "⌘⇧A") {},
                CommandItem(icon: "plus.circle", title: "New Session") {},
                CommandItem(icon: "gearshape", title: "Settings", shortcut: "⌘,") {},
            ]
        )
    }
    .frame(width: 600, height: 500)
}
