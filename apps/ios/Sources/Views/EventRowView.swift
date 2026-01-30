import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct EventRowView: View {
    let event: ConversationEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: event.type.icon)
                .font(.title3)
                .foregroundColor(categoryColor)
                .frame(width: 32, height: 32)
                .background(categoryColor.opacity(0.15))
                .cornerRadius(8)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Event type
                Text(eventTypeDisplay)
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Payload
                if let payloadText = extractPayloadText() {
                    Text(payloadText)
                        .font(.callout)
                        .foregroundColor(.primary)
                        .lineLimit(10)
                }

                // Timestamp
                Text(event.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        #if canImport(UIKit)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Helpers

    private var eventTypeDisplay: String {
        event.type.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var categoryColor: Color {
        switch event.type.category {
        case .output: return .blue
        case .tool: return .purple
        case .question: return .orange
        case .userInput: return .green
        case .file: return Color(red: 0.35, green: 0.34, blue: 0.84) // indigo
        case .execution: return Color(red: 0.19, green: 0.70, blue: 0.90) // cyan
        case .sessionState: return .gray
        case .sessionControl: return .red
        case .health: return Color(red: 0.64, green: 0.96, blue: 0.82) // mint
        case .todo: return .pink
        }
    }

    private func extractPayloadText() -> String? {
        switch event.payload {
        case .text(let string):
            return string

        case .json(let dict):
            // Try to extract common fields
            if let text = extractValue(from: dict, keys: ["text", "message", "content", "output"]) {
                return text
            }

            // Fallback to JSON string
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict.mapValues { $0.value }, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }

            return nil
        }
    }

    private func extractValue(from dict: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] {
                if case .string(let string) = value.value {
                    return string
                }
            }
        }
        return nil
    }
}

// MARK: - Specialized Event Views

struct OutputChunkEventView: View {
    let event: ConversationEvent

    var body: some View {
        EventRowView(event: event)
    }
}

struct ToolEventView: View {
    let event: ConversationEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.title3)
                .foregroundColor(.purple)
                .frame(width: 32, height: 32)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if case .json(let dict) = event.payload,
                   let toolName = extractString(from: dict, key: "toolName") {
                    Text("Tool: \(toolName)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Text(event.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        #if canImport(UIKit)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func extractString(from dict: [String: AnyCodable], key: String) -> String? {
        guard let value = dict[key],
              case .string(let string) = value.value else {
            return nil
        }
        return string
    }
}

#Preview {
    VStack(spacing: 12) {
        EventRowView(event: ConversationEvent(
            eventId: "1",
            sessionId: UUID(),
            type: .outputChunk,
            createdAt: Date(),
            payload: .text("This is a test output chunk event")
        ))

        EventRowView(event: ConversationEvent(
            eventId: "2",
            sessionId: UUID(),
            type: .toolStarted,
            createdAt: Date(),
            payload: .json(["toolName": AnyCodable("bash")])
        ))

        EventRowView(event: ConversationEvent(
            eventId: "3",
            sessionId: UUID(),
            type: .questionAsked,
            createdAt: Date(),
            payload: .text("Would you like to proceed?")
        ))
    }
    .padding()
    #if canImport(UIKit)
    .background(Color(uiColor: .systemGroupedBackground))
    #else
    .background(Color(nsColor: .windowBackgroundColor))
    #endif
}
