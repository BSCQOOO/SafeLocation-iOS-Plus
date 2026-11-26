import Foundation

struct ReleaseCatalog {
    struct Release: Decodable, Sendable {
        let tag_name: String
        let name: String?
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int64
        let browser_download_url: URL
        let digest: String?
    }

    enum CatalogError: LocalizedError {
        case invalid, noRelease
        var errorDescription: String? {
            switch self {
            case .invalid: return "无法验证发布目录响应。"
            case .noRelease: return "仓库没有正式发布版本。"
            }
        }
    }

    static let releasesPage = URL(string: "https://github.com/BSCQOOO/SafeLocation-iOS-Plus/releases")!

    static func latest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/BSCQOOO/SafeLocation-iOS-Plus/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalid }
        if http.statusCode == 404 { throw CatalogError.noRelease }
        guard http.statusCode == 200, data.count <= 2_000_000 else { throw CatalogError.invalid }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, release.html_url.scheme == "https",
              release.html_url.host == "github.com",
              release.html_url.path.hasPrefix("/BSCQOOO/SafeLocation-iOS-Plus/releases/tag/") else { throw CatalogError.invalid }
        return release
    }

    static func version(_ value: String) -> [Int]? {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        let nums = pieces.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            return n
        }
        return nums.count == 3 ? nums : nil
    }

    static func isNewer(_ remote: String, than local: String) -> Bool? {
        guard let a = version(remote), let b = version(local) else { return nil }
        return b.lexicographicallyPrecedes(a)
    }
}
