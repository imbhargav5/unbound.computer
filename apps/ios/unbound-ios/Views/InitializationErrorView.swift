//
//  InitializationErrorView.swift
//  unbound-ios
//
//  Error view shown when app initialization fails
//

import SwiftUI

struct InitializationErrorView: View {
    let error: Error
    let onRetry: () -> Void
    let onRecreateDatabase: (() -> Void)?

    init(
        error: Error,
        onRetry: @escaping () -> Void,
        onRecreateDatabase: (() -> Void)? = nil
    ) {
        self.error = error
        self.onRetry = onRetry
        self.onRecreateDatabase = onRecreateDatabase
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Failed to Start")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 8) {
                Text("Unbound encountered an error during startup:")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding()
                    .background(AppTheme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 320)
            }

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            if let onRecreateDatabase {
                Button("Recreate Local Database and Retry", role: .destructive) {
                    onRecreateDatabase()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundPrimary)
    }
}

#Preview {
    InitializationErrorView(
        error: NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Database migration failed"]
        ),
        onRetry: {},
        onRecreateDatabase: {}
    )
}
