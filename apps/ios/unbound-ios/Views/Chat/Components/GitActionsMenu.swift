import SwiftUI

struct GitActionsMenu: View {
    var onCreatePR: () -> Void = {}
    var onPushChanges: () -> Void = {}
    var onViewFullDiff: () -> Void = {}
    var onCopyChanges: () -> Void = {}
    var onCommit: () -> Void = {}

    var body: some View {
        Menu {
            Section("Git Actions") {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onCreatePR()
                } label: {
                    Label("Create PR", systemImage: "arrow.triangle.pull")
                }

                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onPushChanges()
                } label: {
                    Label("Push Changes", systemImage: "arrow.up.circle")
                }

                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onCommit()
                } label: {
                    Label("Commit", systemImage: "checkmark.circle")
                }
            }

            Section("View") {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onViewFullDiff()
                } label: {
                    Label("View Full Diff", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onCopyChanges()
                } label: {
                    Label("Copy All Changes", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

// MARK: - Alternative Compact Version

struct GitActionsToolbar: View {
    var onCreatePR: () -> Void = {}
    var onPushChanges: () -> Void = {}

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Create PR button
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onCreatePR()
            } label: {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.caption.weight(.medium))
                    Text("PR")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.spacingS)
                .padding(.vertical, AppTheme.spacingXS)
                .background(AppTheme.accentGradient)
                .clipShape(Capsule())
            }

            // Push button
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onPushChanges()
            } label: {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption.weight(.medium))
                    Text("Push")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingS)
                .padding(.vertical, AppTheme.spacingXS)
                .background(AppTheme.toolBadgeBg)
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Previews

#Preview("Git Actions Menu") {
    NavigationStack {
        Text("Chat Content")
            .navigationTitle("Claude Code Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    GitActionsMenu(
                        onCreatePR: { print("Create PR") },
                        onPushChanges: { print("Push") },
                        onViewFullDiff: { print("View Diff") },
                        onCopyChanges: { print("Copy") }
                    )
                }
            }
    }
    .tint(AppTheme.accent)
}

#Preview("Git Actions Toolbar") {
    VStack {
        GitActionsToolbar(
            onCreatePR: { print("Create PR") },
            onPushChanges: { print("Push") }
        )
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}
