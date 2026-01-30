import Foundation

enum ANSI {
    static let reset = "\u{001B}[0m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let gray = "\u{001B}[90m"
    static let white = "\u{001B}[37m"
    static let brightRed = "\u{001B}[91m"
    static let brightGreen = "\u{001B}[92m"
    static let brightYellow = "\u{001B}[93m"
    static let brightBlue = "\u{001B}[94m"
    static let brightMagenta = "\u{001B}[95m"
    static let brightCyan = "\u{001B}[96m"
}
