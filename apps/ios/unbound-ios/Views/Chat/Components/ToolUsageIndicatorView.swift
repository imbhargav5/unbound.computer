import SwiftUI
import Combine

struct ToolUsageIndicatorView: View {
    let toolState: ToolUsageState

    @State private var showText = false
    @State private var dotPhase = 0

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            ClaudeAvatarView(size: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                // Tool badge with spinner
                HStack(spacing: AppTheme.spacingS) {
                    ToolBadgeView(toolName: toolState.toolName)

                    if toolState.isActive {
                        SpinnerView()
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // Status text with fade-in effect
                HStack(spacing: 0) {
                    Text(toolState.statusText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .opacity(showText ? 1 : 0)

                    if toolState.isActive && showText {
                        AnimatedDotsView()
                    }
                }

                // Optional progress bar
                if let progress = toolState.progress, toolState.isActive {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.accent)
                }
            }
            .padding(AppTheme.spacingM)
            .background(AppTheme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AppTheme.spacingM)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                showText = true
            }
        }
        .onChange(of: toolState.statusText) { _, _ in
            showText = false
            withAnimation(.easeIn(duration: 0.2)) {
                showText = true
            }
        }
    }
}

// MARK: - Animated Dots (efficient phase-based animation)

struct AnimatedDotsView: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: phase))
            .font(.subheadline)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(width: 20, alignment: .leading)
            .onReceive(timer) { _ in
                phase = (phase + 1) % 4
            }
    }
}

// MARK: - Tool Badge

struct ToolBadgeView: View {
    let toolName: String

    private var toolType: ToolUsageState.ToolType? {
        ToolUsageState.ToolType(rawValue: toolName)
    }

    private var icon: String {
        toolType?.icon ?? "gearshape"
    }

    var body: some View {
        HStack(spacing: AppTheme.spacingXS) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))

            Text(toolName)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, AppTheme.spacingS)
        .padding(.vertical, AppTheme.spacingXS)
        .background(AppTheme.toolBadgeBg)
        .clipShape(Capsule())
    }
}

// MARK: - Spinner

struct SpinnerView: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(AppTheme.accent, lineWidth: 2)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 1)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Tool History Stack

struct ToolHistoryStackView: View {
    let completedTools: [ToolUsageState]
    let currentTool: ToolUsageState?

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            ClaudeAvatarView(size: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                // Completed tools (collapsed or expanded)
                if !completedTools.isEmpty {
                    if isExpanded {
                        // Show all completed tools
                        ForEach(completedTools, id: \.id) { tool in
                            CompletedToolRow(tool: tool)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    } else {
                        // Show collapsed stack
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded = true
                            }
                        } label: {
                            HStack(spacing: AppTheme.spacingXS) {
                                // Stack of overlapping badges
                                ZStack {
                                    ForEach(Array(completedTools.suffix(3).enumerated()), id: \.offset) { index, tool in
                                        SmallToolBadge(toolName: tool.toolName)
                                            .offset(x: CGFloat(index) * 12)
                                    }
                                }
                                .frame(width: CGFloat(min(completedTools.count, 3)) * 12 + 20)

                                Text("\(completedTools.count) completed")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)

                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .padding(.vertical, AppTheme.spacingXS)
                            .padding(.horizontal, AppTheme.spacingS)
                            .background(AppTheme.backgroundSecondary.opacity(0.5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Current active tool
                if let tool = currentTool {
                    ActiveToolRow(tool: tool)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(AppTheme.spacingM)
            .background(AppTheme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AppTheme.spacingM)
    }
}

// MARK: - Small Tool Badge (for collapsed stack)

struct SmallToolBadge: View {
    let toolName: String

    private var toolType: ToolUsageState.ToolType? {
        ToolUsageState.ToolType(rawValue: toolName)
    }

    private var icon: String {
        toolType?.icon ?? "gearshape"
    }

    var body: some View {
        Image(systemName: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(AppTheme.accent)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(AppTheme.assistantBubble, lineWidth: 2)
            )
    }
}

// MARK: - Completed Tool Row

struct CompletedToolRow: View {
    let tool: ToolUsageState

    var body: some View {
        HStack(spacing: AppTheme.spacingS) {
            ToolBadgeView(toolName: tool.toolName)

            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            Text(tool.statusText)
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, AppTheme.spacingXS)
    }
}

// MARK: - Active Tool Row

struct ActiveToolRow: View {
    let tool: ToolUsageState

    @State private var showText = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            HStack(spacing: AppTheme.spacingS) {
                ToolBadgeView(toolName: tool.toolName)
                SpinnerView()
            }

            HStack(spacing: 0) {
                Text(tool.statusText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .opacity(showText ? 1 : 0)

                if showText {
                    AnimatedDotsView()
                }
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                showText = true
            }
        }
        .onChange(of: tool.statusText) { _, _ in
            showText = false
            withAnimation(.easeIn(duration: 0.2)) {
                showText = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Tool Usage - Active") {
    VStack(spacing: 20) {
        ToolUsageIndicatorView(
            toolState: ToolUsageState(
                toolName: "Read",
                statusText: "Reading ChatView.swift",
                isActive: true
            )
        )

        ToolUsageIndicatorView(
            toolState: ToolUsageState(
                toolName: "Grep",
                statusText: "Searching for related patterns",
                isActive: true
            )
        )

        ToolUsageIndicatorView(
            toolState: ToolUsageState(
                toolName: "Write",
                statusText: "Generating new component",
                isActive: true,
                progress: 0.6
            )
        )
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}

#Preview("Tool Usage - Completed") {
    ToolUsageIndicatorView(
        toolState: ToolUsageState(
            toolName: "Read",
            statusText: "Read ChatView.swift",
            isActive: false
        )
    )
    .padding()
    .background(AppTheme.backgroundPrimary)
}

#Preview("Tool Badge") {
    HStack(spacing: 10) {
        ToolBadgeView(toolName: "Read")
        ToolBadgeView(toolName: "Write")
        ToolBadgeView(toolName: "Grep")
        ToolBadgeView(toolName: "Bash")
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}
