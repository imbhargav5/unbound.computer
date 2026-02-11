//
//  OnboardingView.swift
//  unbound-ios
//
//  Onboarding flow shown on first launch before authentication.
//  Three pages: Welcome, Multi-Device, Sessions overview.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0

    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                multiDevicePage.tag(1)
                sessionsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Page indicator + navigation buttons
            VStack(spacing: AppTheme.spacingL) {
                pageIndicator

                navigationButtons
            }
            .padding(.horizontal, AppTheme.spacingL)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: AppTheme.spacingL) {
            Spacer()

            // Logo
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.white)
            }
            .padding(.bottom, AppTheme.spacingM)

            // Title
            Text("Welcome to Unbound")
                .font(Typography.title)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

            // Description
            Text("Monitor and manage your Claude Code sessions from anywhere. Stay connected to your development workflow.")
                .font(Typography.body)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingL)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    // MARK: - Page 2: Multi-Device

    private var multiDevicePage: some View {
        VStack(spacing: AppTheme.spacingL) {
            Spacer()

            // Device cards preview
            VStack(spacing: AppTheme.spacingS) {
                OnboardingDeviceCard(
                    icon: "laptopcomputer",
                    name: "MacBook Pro",
                    status: "Online",
                    statusColor: .green
                )

                OnboardingDeviceCard(
                    icon: "desktopcomputer",
                    name: "Linux Desktop",
                    status: "Offline",
                    statusColor: .gray
                )
            }
            .padding(.horizontal, AppTheme.spacingL)

            // Title
            Text("Seamless Multi-Device")
                .font(Typography.title)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.spacingM)

            // Description
            Text("Connect all your development machines and switch between them effortlessly.")
                .font(Typography.body)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingL)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    // MARK: - Page 3: Sessions

    private var sessionsPage: some View {
        VStack(spacing: AppTheme.spacingL) {
            Spacer()

            // Session list preview
            VStack(spacing: AppTheme.spacingS) {
                OnboardingSessionRow(
                    title: "Feature Implementation",
                    time: "2 min ago",
                    statusColor: .green
                )

                OnboardingSessionRow(
                    title: "API Integration",
                    time: "1 hour ago",
                    statusColor: .yellow
                )

                OnboardingSessionRow(
                    title: "Bug Fix Session",
                    time: "Yesterday",
                    statusColor: .gray
                )
            }
            .padding(.horizontal, AppTheme.spacingL)

            // Title
            Text("All Your Sessions, One Place")
                .font(Typography.title)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.spacingM)

            // Description
            Text("View, manage, and continue your Claude Code sessions across all your connected devices.")
                .font(Typography.body)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingL)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: AppTheme.spacingS) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            // Left button: Skip (page 0) or Back (pages 1-2)
            Button {
                if currentPage == 0 {
                    completeOnboarding()
                } else {
                    withAnimation {
                        currentPage -= 1
                    }
                }
            } label: {
                Text(currentPage == 0 ? "Skip" : "Back")
                    .font(Typography.body)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingM)
            }
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))

            // Right button: Next (pages 0-1) or Get Started (page 2)
            Button {
                if currentPage < totalPages - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(currentPage == totalPages - 1 ? "Get Started" : "Next")
                    .font(Typography.headline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingM)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        }
    }

    // MARK: - Actions

    private func completeOnboarding() {
        logger.info("Onboarding completed")
        onComplete()
    }
}

// MARK: - Onboarding Device Card

private struct OnboardingDeviceCard: View {
    let icon: String
    let name: String
    let status: String
    let statusColor: Color

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.white)

                HStack(spacing: AppTheme.spacingXS) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(status)
                        .font(Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(AppTheme.spacingM)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Onboarding Session Row

private struct OnboardingSessionRow: View {
    let title: String
    let time: String
    let statusColor: Color

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.white)

                Text(time)
                    .font(Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(AppTheme.spacingM)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingView {
        logger.debug("Onboarding completed in preview")
    }
}
