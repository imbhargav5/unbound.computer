//
//  PostLoginSyncWrapper.swift
//  unbound-ios
//
//  Wrapper view that performs post-login sync before showing main content.
//  Syncs repositories and sessions from Supabase into local SQLite.
//

import SwiftUI

/// Wrapper view that performs post-login sync before showing main content
struct PostLoginSyncWrapper<Content: View>: View {
    @State private var syncService: PostLoginSyncService?
    @State private var hasSynced = false
    @State private var syncError: Error?

    private let syncedDataService = SyncedDataService.shared
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if hasSynced {
                content()
            } else {
                syncingView
            }
        }
        .task {
            await performSync()
        }
    }

    // MARK: - Syncing View

    @ViewBuilder
    private var syncingView: some View {
        VStack(spacing: 16) {
            if let service = syncService {
                // Show progress
                VStack(spacing: 12) {
                    ProgressView(value: service.syncProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)

                    Text(service.syncMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                // Initial loading state
                ProgressView()

                Text("Preparing...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let error = syncError {
                VStack(spacing: 8) {
                    Text("Sync error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)

                    Button("Continue Anyway") {
                        hasSynced = true
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sync Logic

    private func performSync() async {
        let service = PostLoginSyncService()
        syncService = service

        // Sync data from Supabase to local SQLite
        await service.performPostLoginSync()

        // Load synced data into the service for UI access
        await syncedDataService.loadAll()

        if let error = service.syncError {
            syncError = error
            // Still allow user to continue after a short delay
            try? await Task.sleep(for: .seconds(2))
        }

        hasSynced = true
    }
}

#Preview {
    PostLoginSyncWrapper {
        Text("Main Content")
    }
}
