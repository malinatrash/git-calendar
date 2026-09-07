import Foundation

struct AppRelease: Identifiable, Sendable {
    var id: String { version }
    let version: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL
}

struct SemanticVersion: Comparable, Equatable {
    let components: [Int]

    init(_ rawValue: String) {
        components = rawValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct UpdateChecker: Sendable {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let body: String?
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    func latestReleaseIfNewer(currentVersion: String) async throws -> AppRelease? {
        guard let repository = Bundle.main.object(forInfoDictionaryKey: "GitHubRepository") as? String,
              let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitCalendar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard SemanticVersion(currentVersion) < SemanticVersion(release.tagName) else { return nil }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return AppRelease(
            version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            notes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            pageURL: release.htmlURL,
            downloadURL: dmg?.browserDownloadURL ?? release.htmlURL
        )
    }
}
