import SwiftUI

struct DynamicIslandView: View {
    let sessions: [ActiveSession]
    @Binding var isExpanded: Bool
    let onSessionTap: (ActiveSession) -> Void

    @State private var appearAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Active Sessions")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                // Close button
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.white.opacity(0.2))
                .padding(.horizontal, 16)

            // Sessions list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        SessionRowView(session: session) {
                            onSessionTap(session)
                        }
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 20)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.75)
                                .delay(Double(index) * 0.05),
                            value: appearAnimation
                        )
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 400)
        }
        .background(.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 44)) // More pill-like, matching Dynamic Island
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 8) // Tighter to edges like real Dynamic Island
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appearAnimation = true
            }
        }
        .onDisappear {
            appearAnimation = false
        }
    }
}

// MARK: - Overlay Modifier

struct DynamicIslandOverlay: ViewModifier {
    @Binding var isExpanded: Bool
    let sessions: [ActiveSession]
    let onSessionTap: (ActiveSession) -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if isExpanded {
                // Backdrop
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isExpanded = false
                        }
                    }
                    .transition(.opacity)

                // Island - positioned at top near notch
                DynamicIslandView(
                    sessions: sessions,
                    isExpanded: $isExpanded,
                    onSessionTap: onSessionTap
                )
                .padding(.top, 12) // Right below the Dynamic Island notch area
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .top)),
                        removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .top))
                    )
                )
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
    }
}

extension View {
    func dynamicIslandOverlay(
        isExpanded: Binding<Bool>,
        sessions: [ActiveSession],
        onSessionTap: @escaping (ActiveSession) -> Void
    ) -> some View {
        modifier(DynamicIslandOverlay(
            isExpanded: isExpanded,
            sessions: sessions,
            onSessionTap: onSessionTap
        ))
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isExpanded = true

        var body: some View {
            NavigationStack {
                Color.gray.opacity(0.1)
                    .ignoresSafeArea()
                    .navigationTitle("Chat")
            }
            .dynamicIslandOverlay(
                isExpanded: $isExpanded,
                sessions: [
                    ActiveSession(
                        id: UUID(),
                        projectName: "rocketry-ios",
                        chatTitle: "Implement device list",
                        deviceName: "MacBook Pro",
                        status: .generating,
                        progress: 0.65,
                        startedAt: Date(),
                        language: .swift
                    ),
                    ActiveSession(
                        id: UUID(),
                        projectName: "claude-code",
                        chatTitle: "Fix navigation",
                        deviceName: "MacBook Pro",
                        status: .prReady,
                        progress: 1.0,
                        startedAt: Date().addingTimeInterval(-300),
                        language: .typescript
                    ),
                    ActiveSession(
                        id: UUID(),
                        projectName: "ml-pipeline",
                        chatTitle: "Add validation",
                        deviceName: "Mac Mini",
                        status: .merged,
                        progress: 1.0,
                        startedAt: Date().addingTimeInterval(-600),
                        language: .python
                    )
                ]
            ) { session in
                print("Tapped: \(session.projectName)")
            }
        }
    }

    return PreviewWrapper()
}
