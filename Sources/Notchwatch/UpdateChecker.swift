import Foundation

struct UpdateInfo: Equatable {
    let version: String
    let url: URL
}

/// Comprueba si hay una release más nueva en GitHub. El repo es privado, así que necesita un
/// token de GitHub de solo lectura (opcional, guardado en el Llavero).
enum UpdateChecker {
    static let releasesPage = URL(string: "https://github.com/JoanDevandTech/notchwatch/releases")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/JoanDevandTech/notchwatch/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func latest(token: String) async throws -> UpdateInfo? {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // 404: todavía no hay ninguna release publicada.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else {
            throw URLError(http.statusCode == 401 || http.statusCode == 403 ? .userAuthenticationRequired : .badServerResponse)
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard isNewer(version, than: currentVersion), let url = URL(string: release.htmlURL) else { return nil }
        return UpdateInfo(version: version, url: url)
    }

    /// Compara versiones semánticas numéricas ("0.10.1" > "0.9.3"). Ignora sufijos tipo "-beta".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            let core = version.split(separator: "-").first.map(String.init) ?? version
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let lhs = parts(candidate)
        let rhs = parts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
