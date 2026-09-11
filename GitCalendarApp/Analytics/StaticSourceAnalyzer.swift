import Foundation

enum StaticSourceAnalyzer {
    private static let branchPattern = try! NSRegularExpression(
        pattern: #"\b(if|else\s+if|for|while|case|catch|when|guard)\b|&&|\|\||\s\?\s"#,
        options: [.caseInsensitive]
    )
    private static let dependencyPattern = try! NSRegularExpression(
        pattern: #"^\s*(import|from|include|require|use|using)\b"#,
        options: [.caseInsensitive]
    )
    private static let functionPattern = try! NSRegularExpression(
        pattern: #"\b(func|function|def|fn)\s+[A-Za-z_]|\b[A-Za-z_][A-Za-z0-9_]*\s*\([^;]*\)\s*(throws\s*)?(->[^\{]+)?\{"#
    )

    static func analyze(_ source: String, path: String) -> SourceMetrics {
        let lines = source.components(separatedBy: .newlines)
        var codeLines = 0
        var commentLines = 0
        var longLines = 0
        var cyclomatic = 1
        var dependencies: Set<String> = []
        var maximumNesting = 0
        var braceNesting = 0
        var indentationLevels: [Int] = []
        var functionStarts: [(line: Int, braceDepth: Int)] = []
        var functionLengths: [Int] = []
        var inBlockComment = false
        var inDependencyBlock = false

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if inBlockComment {
                commentLines += 1
                if trimmed.contains("*/") { inBlockComment = false }
                continue
            }
            if trimmed.hasPrefix("/*") {
                commentLines += 1
                inBlockComment = !trimmed.contains("*/")
                continue
            }
            if isLineComment(trimmed, path: path) {
                commentLines += 1
                continue
            }

            codeLines += 1
            if rawLine.count > 120 { longLines += 1 }
            cyclomatic += matches(branchPattern, in: rawLine)
            if trimmed == "import (" {
                inDependencyBlock = true
            } else if inDependencyBlock, trimmed == ")" {
                inDependencyBlock = false
            } else if inDependencyBlock, trimmed.contains("\"") {
                dependencies.insert(trimmed)
            } else if matches(dependencyPattern, in: rawLine) > 0 {
                dependencies.insert(trimmed)
            }

            let leadingClosures = trimmed.prefix { $0 == "}" }.count
            braceNesting = max(0, braceNesting - leadingClosures)
            let indentation = rawLine.prefix { $0 == " " || $0 == "\t" }.reduce(0) {
                $0 + ($1 == "\t" ? 4 : 1)
            }
            while let last = indentationLevels.last, last >= indentation { indentationLevels.removeLast() }
            if usesIndentation(path), indentation > 0,
               indentationLevels.last.map({ indentation > $0 }) ?? true {
                indentationLevels.append(indentation)
            }
            maximumNesting = max(maximumNesting, usesIndentation(path) ? indentationLevels.count : braceNesting)

            if usesIndentation(path) {
                while let current = functionStarts.last,
                      indentation <= current.braceDepth,
                      index > current.line {
                    functionLengths.append(index - current.line)
                    functionStarts.removeLast()
                }
            }
            if isFunctionDeclaration(rawLine) {
                functionStarts.append((index, usesIndentation(path) ? indentation : braceNesting))
            }

            let openings = rawLine.filter { $0 == "{" }.count
            let closings = rawLine.filter { $0 == "}" }.count - leadingClosures
            braceNesting = max(0, braceNesting + openings - max(0, closings))

            while let current = functionStarts.last,
                  (!usesIndentation(path) && braceNesting <= current.braceDepth && index > current.line) {
                functionLengths.append(index - current.line + 1)
                functionStarts.removeLast()
            }
        }

        for current in functionStarts { functionLengths.append(lines.count - current.line) }
        let describedLines = codeLines + commentLines
        return SourceMetrics(
            codeLines: codeLines,
            commentRatio: describedLines == 0 ? 0 : Double(commentLines) / Double(describedLines),
            longLineRatio: codeLines == 0 ? 0 : Double(longLines) / Double(codeLines),
            cyclomaticComplexity: codeLines == 0 ? 0 : cyclomatic,
            maximumNesting: maximumNesting,
            dependencyCount: dependencies.count,
            functionCount: functionLengths.count,
            maximumFunctionLength: functionLengths.max() ?? 0
        )
    }

    private static func matches(_ expression: NSRegularExpression, in value: String) -> Int {
        expression.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value))
    }

    private static func isFunctionDeclaration(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        let controlPrefixes = ["if", "for", "while", "switch", "catch", "guard"]
        guard !controlPrefixes.contains(where: { trimmed.hasPrefix($0 + " ") || trimmed.hasPrefix($0 + "(") }) else {
            return false
        }
        return matches(functionPattern, in: line) > 0
    }

    private static func isLineComment(_ line: String, path: String) -> Bool {
        if line.hasPrefix("//") || line.hasPrefix("#") || line.hasPrefix("--") { return true }
        return SourceClassifier.languageKey(for: path) == "sql" && line.hasPrefix("/*")
    }

    private static func usesIndentation(_ path: String) -> Bool {
        ["py", "rb", "yaml", "yml"].contains(SourceClassifier.languageKey(for: path))
    }
}
