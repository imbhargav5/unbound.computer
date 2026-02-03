//
//  WatchMCQ.swift
//  mockup-watchos Watch App
//

import Foundation

struct WatchMCQ: Identifiable, Hashable {
    let id: String
    let question: String
    let options: [String]
    let allowsCustomInput: Bool

    init(
        id: String = UUID().uuidString,
        question: String,
        options: [String],
        allowsCustomInput: Bool = true
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.allowsCustomInput = allowsCustomInput
    }
}
