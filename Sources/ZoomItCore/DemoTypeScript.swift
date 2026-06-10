import Foundation

/// Parser and cursor for DemoType script files.
///
/// File format (compatible with ZoomIt's documented behavior):
///   - The file is a sequence of snippets. Each snippet is typed verbatim,
///     including newlines.
///   - A line consisting solely of `[end]` (case-insensitive) separates
///     snippets and is not typed.
///   - `[pause:N]` on its own inside text inserts a pause of N tenths of a
///     second while typing.
public struct DemoTypeScript: Equatable, Sendable {
    public enum Element: Equatable, Sendable {
        case typeText(String)
        case pause(TimeInterval)
    }

    public struct Snippet: Equatable, Sendable {
        public var elements: [Element]
        public init(elements: [Element]) { self.elements = elements }

        /// Full text of the snippet with pauses removed (useful for tests/preview).
        public var plainText: String {
            elements.compactMap {
                if case .typeText(let t) = $0 { return t }
                return nil
            }.joined()
        }
    }

    public var snippets: [Snippet]

    public init(snippets: [Snippet]) {
        self.snippets = snippets
    }

    public static func parse(_ contents: String) -> DemoTypeScript {
        // Normalize line endings.
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var snippets: [Snippet] = []
        var currentText = ""
        var currentElements: [Element] = []

        func flushText() {
            if !currentText.isEmpty {
                currentElements.append(.typeText(currentText))
                currentText = ""
            }
        }
        func flushSnippet() {
            flushText()
            // Trim a single trailing newline left by the [end] separator line.
            if case .typeText(var t)? = currentElements.last, t.hasSuffix("\n") {
                t.removeLast()
                currentElements.removeLast()
                if !t.isEmpty { currentElements.append(.typeText(t)) }
            }
            if !currentElements.isEmpty {
                snippets.append(Snippet(elements: currentElements))
            }
            currentElements = []
        }

        let lines = normalized.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "[end]" {
                flushSnippet()
                continue
            }
            // Scan the line for [pause:N] tokens.
            var rest = Substring(line)
            while let open = rest.range(of: "[pause:", options: .caseInsensitive),
                  let close = rest[open.upperBound...].firstIndex(of: "]") {
                currentText += rest[..<open.lowerBound]
                let numberPart = rest[open.upperBound..<close]
                if let tenths = Double(numberPart) {
                    flushText()
                    currentElements.append(.pause(tenths / 10.0))
                } else {
                    currentText += rest[open.lowerBound...close]
                }
                rest = rest[rest.index(after: close)...]
            }
            currentText += rest
            if index < lines.count - 1 {
                currentText += "\n"
            }
        }
        flushSnippet()
        return DemoTypeScript(snippets: snippets)
    }

    public static func load(from url: URL) throws -> DemoTypeScript {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return parse(contents)
    }
}

/// Tracks the current snippet across DemoType invocations, mirroring ZoomIt:
/// Ctrl+7 types the next snippet, Ctrl+Shift+7 moves back one snippet.
public final class DemoTypeCursor {
    public private(set) var index: Int = 0
    public let script: DemoTypeScript

    public init(script: DemoTypeScript) {
        self.script = script
    }

    public var isAtEnd: Bool { index >= script.snippets.count }

    /// The snippet Ctrl+7 should type now, advancing the cursor.
    public func nextSnippet() -> DemoTypeScript.Snippet? {
        guard index < script.snippets.count else { return nil }
        defer { index += 1 }
        return script.snippets[index]
    }

    /// Ctrl+Shift+7: step back so the previous snippet is retyped next.
    public func moveBack() {
        index = max(0, index - 1)
    }

    public func reset() {
        index = 0
    }
}
