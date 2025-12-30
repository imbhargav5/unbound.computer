import Foundation
import SwiftUI

struct Project: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let language: ProjectLanguage
    let lastAccessed: Date
    let chatCount: Int
    let description: String?
    let isFavorite: Bool

    enum ProjectLanguage: String, CaseIterable, Codable {
        case swift = "Swift"
        case typescript = "TypeScript"
        case javascript = "JavaScript"
        case python = "Python"
        case rust = "Rust"
        case go = "Go"
        case ruby = "Ruby"
        case java = "Java"
        case kotlin = "Kotlin"
        case csharp = "C#"
        case cpp = "C++"
        case other = "Other"

        var iconName: String {
            switch self {
            case .swift:
                return "swift"
            case .typescript, .javascript, .python, .go, .cpp:
                return "chevron.left.forwardslash.chevron.right"
            case .rust:
                return "gearshape.2"
            case .ruby:
                return "diamond"
            case .java, .kotlin:
                return "cup.and.saucer"
            case .csharp:
                return "number"
            case .other:
                return "doc.text"
            }
        }

        var color: Color {
            switch self {
            case .swift:
                return Color.orange
            case .typescript:
                return Color.blue
            case .javascript:
                return Color.yellow
            case .python:
                return Color(red: 55/255, green: 118/255, blue: 171/255)
            case .rust:
                return Color(red: 183/255, green: 65/255, blue: 14/255)
            case .go:
                return Color.cyan
            case .ruby:
                return Color.red
            case .java, .kotlin:
                return Color(red: 176/255, green: 114/255, blue: 25/255)
            case .csharp:
                return Color.purple
            case .cpp:
                return Color(red: 0/255, green: 89/255, blue: 156/255)
            case .other:
                return AppTheme.accent
            }
        }
    }
}
