//
//  ContentView.swift
//  mockup-watchos Watch App
//
//  Created by Bhargav Ponnapalli on 02/02/26.
//

import SwiftUI

// MARK: - Main Tab View

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SessionListView()
                .tag(0)

            DeviceListView()
                .tag(1)

            SettingsView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var hapticEnabled = true
    @State private var notificationsEnabled = true
    @State private var showComplicationPreview = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Notifications", systemImage: "bell.fill")
                    }

                    Toggle(isOn: $hapticEnabled) {
                        Label("Haptics", systemImage: "waveform")
                    }
                }

                Section {
                    Button {
                        showComplicationPreview = true
                    } label: {
                        Label("Complications", systemImage: "watchface.applewatch.case")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showComplicationPreview) {
                ComplicationPreviewView()
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.spacingL) {
                // App icon placeholder
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 50, height: 50)

                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }

                VStack(spacing: WatchTheme.spacingS) {
                    Text("Unbound")
                        .font(.system(size: 17, weight: .bold))

                    Text("Version 1.0.0")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Text("Remote control for Claude Code sessions running on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, WatchTheme.spacingL)
        }
        .navigationTitle("About")
    }
}

// MARK: - Complication Preview View

struct ComplicationPreviewView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WatchTheme.spacingL) {
                    Text("Complications")
                        .font(.system(size: 15, weight: .semibold))

                    // Circular preview
                    VStack(spacing: WatchTheme.spacingS) {
                        Text("Circular")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        CircularComplicationView(
                            entry: SessionComplicationEntry(
                                date: Date(),
                                sessionCount: 3,
                                activeCount: 2,
                                waitingCount: 1,
                                hasError: false
                            )
                        )
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 1))
                    }

                    // Rectangular preview
                    VStack(spacing: WatchTheme.spacingS) {
                        Text("Rectangular")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        RectangularComplicationView(
                            entry: SessionComplicationEntry(
                                date: Date(),
                                sessionCount: 3,
                                activeCount: 2,
                                waitingCount: 1,
                                hasError: false
                            )
                        )
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3), lineWidth: 1))
                    }

                    Text("Add to your watch face from the Watch app on iPhone")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Previews

#Preview("Main Tab View") {
    MainTabView()
}

#Preview("Settings") {
    SettingsView()
}

#Preview("About") {
    NavigationStack {
        AboutView()
    }
}

#Preview("Complications") {
    ComplicationPreviewView()
}
