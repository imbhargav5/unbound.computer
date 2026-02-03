//
//  MCQReplyView.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct MCQReplyView: View {
    let mcq: WatchMCQ
    let onAnswer: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customInput = ""
    @State private var showCustomInput = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WatchTheme.spacingM) {
                    // Question
                    questionHeader

                    // Options
                    optionsList

                    // Custom input option
                    if mcq.allowsCustomInput {
                        customInputButton
                    }
                }
                .padding(.horizontal, WatchTheme.spacingS)
            }
            .navigationTitle("Question")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCustomInput) {
                customInputSheet
            }
        }
    }

    private var questionHeader: some View {
        VStack(spacing: WatchTheme.spacingS) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)

            Text(mcq.question)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, WatchTheme.spacingM)
    }

    private var optionsList: some View {
        VStack(spacing: WatchTheme.spacingS) {
            ForEach(mcq.options, id: \.self) { option in
                Button {
                    selectOption(option)
                } label: {
                    HStack {
                        Text(option)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Image(systemName: "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(WatchTheme.spacingM)
                    .background(WatchTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WatchTheme.cornerRadiusMedium))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customInputButton: some View {
        Button {
            showCustomInput = true
            HapticManager.buttonTap()
        } label: {
            HStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)

                Text("Something else")
                    .font(.system(size: 13))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(WatchTheme.spacingM)
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: WatchTheme.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
    }

    private var customInputSheet: some View {
        NavigationStack {
            VStack(spacing: WatchTheme.spacingM) {
                Text("Dictate your response")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Type or dictate", text: $customInput)
                    .textFieldStyle(.plain)
                    .padding(WatchTheme.spacingM)
                    .background(WatchTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WatchTheme.cornerRadiusMedium))

                Button("Send") {
                    if !customInput.isEmpty {
                        selectOption(customInput)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(customInput.isEmpty)
            }
            .padding()
            .navigationTitle("Custom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCustomInput = false
                    }
                }
            }
        }
    }

    private func selectOption(_ option: String) {
        HapticManager.selection()
        onAnswer(option)
        dismiss()
    }
}

#Preview("MCQ Reply") {
    MCQReplyView(
        mcq: WatchMockData.sampleMCQs[0]
    ) { answer in
        print("Selected: \(answer)")
    }
}

#Preview("MCQ Yes/No") {
    MCQReplyView(
        mcq: WatchMockData.sampleMCQs[2]
    ) { answer in
        print("Selected: \(answer)")
    }
}
