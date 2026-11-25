import Foundation

enum ModrinthError: LocalizedError {
    case invalidURL
    case badStatusCode(Int)
    case noCompatibleFile

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный URL запроса к Modrinth."
        case .badStatusCode(let code):
            return "Modrinth API вернул код \(code)."
        case .noCompatibleFile:
            return "У выбранного проекта нет доступного файла для загрузки."
        }
    }
}

final class ModrinthClient {
    static let shared = ModrinthClient()

    private let baseURL = "https://api.modrinth.com/v2"
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "MCRustLauncher-iOS/0.1.0 (custom-rust-client)"
        ]
        session = URLSession(configuration: config)
    }

    func search(query: String, kind: ContentKind, limit: Int = 25) async throws -> [ModrinthProject] {
        var components = URLComponents(string: "\(baseURL)/search")
        let facets = "[[\"project_type:\(kind.modrinthProjectType)\"]]"
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "facets", value: facets),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "index", value: "downloads")
        ]

        guard let url = components?.url else {
            throw ModrinthError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ModrinthError.badStatusCode(http.statusCode)
        }

        let decoded = try decoder.decode(ModrinthSearchResponse.self, from: data)
        return decoded.hits
    }

    func fetchVersions(projectId: String) async throws -> [ModrinthVersion] {
        guard let url = URL(string: "\(baseURL)/project/\(projectId)/version") else {
            throw ModrinthError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ModrinthError.badStatusCode(http.statusCode)
        }

        return try decoder.decode([ModrinthVersion].self, from: data)
    }

    func downloadLatestFile(projectId: String) async throws -> (fileName: String, data: Data) {
        let versions = try await fetchVersions(projectId: projectId)
        guard let latest = versions.first,
              let file = latest.files.first(where: { $0.primary }) ?? latest.files.first,
              let fileURL = URL(string: file.url) else {
            throw ModrinthError.noCompatibleFile
        }

        let (data, response) = try await session.data(from: fileURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ModrinthError.badStatusCode(http.statusCode)
        }

        return (file.filename, data)
    }
}
