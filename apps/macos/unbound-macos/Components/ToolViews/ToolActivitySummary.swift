//
//  ToolActivitySummary.swift
//  unbound-macos
//
//  Helper for rendering lightweight tool activity summaries and action lines.
//

import Foundation

struct ToolActionLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

enum ToolActivitySummary {
    static func summary(for subagentType: String, tools: [ToolUse], status: ToolStatus) -> String {
        let counts = categoryCounts(toolNames: tools.map { $0.toolName })
        let countsText = formatCounts(counts)
        guard let verb = verbForSubagent(type: subagentType, status: status) else {
            return "\(subagentType) activity"
        }
        if countsText.isEmpty {
            return verb
        }
        return "\(verb) \(countsText)"
    }

    static func summary(for tools: [ActiveTool]) -> String {
        let counts = categoryCounts(toolNames: tools.map { $0.name })
        let countsText = formatCounts(counts)
        let verb = tools.contains(where: { $0.status == .running }) ? "Running" : "Ran"
        if countsText.isEmpty {
            return verb
        }
        return "\(verb) \(countsText)"
    }

    static func actionLines(for tools: [ToolUse]) -> [ToolActionLine] {
        tools.map { tool in
            let parser = ToolInputParser(tool.input)
            let text: String
            switch tool.toolName {
            case "Read":
                text = "Read \(fileLabel(parser.filePath))"
            case "Write":
                text = "Wrote \(fileLabel(parser.filePath))"
            case "Edit":
                text = "Edited \(fileLabel(parser.filePath))"
            case "Grep":
                text = "Searched for \(parser.pattern ?? "")"
            case "Glob":
                text = "Searched files by \(parser.pattern ?? "")"
            case "Bash":
                text = "Ran \(parser.command ?? parser.commandDescription ?? "")"
            case "WebSearch":
                text = "Searched the web for \(parser.query ?? "")"
            case "WebFetch":
                text = "Fetched \(hostLabel(parser.url))"
            default:
                text = fallbackText(toolName: tool.toolName, preview: parser.taskDescription ?? parser.filePath ?? parser.pattern ?? parser.query ?? parser.command ?? parser.url ?? "")
            }
            return ToolActionLine(text: text.trimmingCharacters(in: .whitespaces))
        }
        .filter { !$0.text.isEmpty }
    }

    static func actionLine(for tool: ToolUse) -> ToolActionLine? {
        actionLines(for: [tool]).first
    }

    static func actionLines(for tools: [ActiveTool]) -> [ToolActionLine] {
        tools.map { tool in
            let preview = tool.inputPreview ?? ""
            let text: String
            switch tool.name {
            case "Read":
                text = "Read \(fileLabel(preview))"
            case "Write":
                text = "Wrote \(fileLabel(preview))"
            case "Edit":
                text = "Edited \(fileLabel(preview))"
            case "Grep":
                text = "Searched for \(preview)"
            case "Glob":
                text = "Searched files by \(preview)"
            case "Bash":
                text = "Ran \(preview)"
            case "WebSearch":
                text = "Searched the web for \(preview)"
            case "WebFetch":
                text = "Fetched \(hostLabel(preview))"
            default:
                text = fallbackText(toolName: tool.name, preview: preview)
            }
            return ToolActionLine(text: text.trimmingCharacters(in: .whitespaces))
        }
        .filter { !$0.text.isEmpty }
    }

    private static func verbForSubagent(type: String, status: ToolStatus) -> String? {
        let lower = type.lowercased()
        let isRunning = status == .running
        switch lower {
        case "explore":
            return isRunning ? "Exploring" : "Explored"
        case "plan":
            return isRunning ? "Planning" : "Planned"
        case "bash":
            return isRunning ? "Running" : "Ran"
        case "general-purpose":
            return isRunning ? "Working" : "Worked"
        default:
            return nil
        }
    }

    private static func categoryCounts(toolNames: [String]) -> (files: Int, searches: Int, commands: Int, web: Int) {
        var files = 0
        var searches = 0
        var commands = 0
        var web = 0

        for name in toolNames {
            switch name {
            case "Read", "Write", "Edit":
                files += 1
            case "Grep", "Glob":
                searches += 1
            case "Bash":
                commands += 1
            case "WebSearch", "WebFetch":
                web += 1
            default:
                break
            }
        }

        return (files, searches, commands, web)
    }

    private static func formatCounts(_ counts: (files: Int, searches: Int, commands: Int, web: Int)) -> String {
        var parts: [String] = []

        if counts.files > 0 {
            parts.append(formatCount(counts.files, singular: "file", plural: "files"))
        }
        if counts.searches > 0 {
            parts.append(formatCount(counts.searches, singular: "search", plural: "searches"))
        }
        if counts.commands > 0 {
            parts.append(formatCount(counts.commands, singular: "command", plural: "commands"))
        }
        if counts.web > 0 {
            parts.append(formatCount(counts.web, singular: "web request", plural: "web requests"))
        }

        return parts.joined(separator: ", ")
    }

    private static func formatCount(_ count: Int, singular: String, plural: String) -> String {
        if count == 1 {
            return "1 \(singular)"
        }
        return "\(count) \(plural)"
    }

    private static func fileLabel(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func hostLabel(_ urlString: String?) -> String {
        guard let urlString, !urlString.isEmpty else { return "" }
        if let url = URL(string: urlString), let host = url.host {
            return host
        }
        return urlString
    }

    private static func fallbackText(toolName: String, preview: String) -> String {
        if preview.isEmpty {
            return toolName
        }
        return "\(toolName) \(preview)"
    }
}
