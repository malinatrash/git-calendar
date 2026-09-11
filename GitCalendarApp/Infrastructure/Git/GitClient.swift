import Foundation

protocol GitCommandRunning: Sendable {
    func output(_ arguments: [String], in repository: URL?) throws -> String
}

struct SystemGitClient: GitCommandRunning {
    struct CommandError: LocalizedError {
        let arguments: [String]
        let message: String

        var errorDescription: String? {
            message.isEmpty ? "git завершился с ошибкой: \(arguments.joined(separator: " "))" : message
        }
    }

    func output(_ arguments: [String], in repository: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = repository.map { ["-C", $0.path] + arguments } ?? arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C.UTF-8"]) { _, new in new }

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError(
                arguments: process.arguments ?? arguments,
                message: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return String(decoding: data, as: UTF8.self)
    }
}
