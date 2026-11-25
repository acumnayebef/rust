import Foundation

enum HorizonCatalogError: LocalizedError {
    case missingBundledCatalog
    case invalidURL
    case downloadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingBundledCatalog:
            return "Не найден встроенный каталог Horizon (horizon-index.json)."
        case .invalidURL:
            return "Некорректный URL загрузки мода Horizon."
        case .downloadFailed(let code):
            return "Сервер вернул код \(code) при загрузке файла Horizon."
        }
    }
}

final class HorizonCatalogService {
    static let shared = HorizonCatalogService()

    private let remoteIndexURL = URL(string: "https://horizon-rust.github.io/horizon-mods/index.json")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "EternalLauncher-iOS/0.2.0 (Horizon)"
        ]
        session = URLSession(configuration: config)
    }

    func loadBundledOrCached() -> [HorizonProject] {
        let cachedURL = FileSystemManager.shared.cachedHorizonIndexURL
        if let cachedData = try? Data(contentsOf: cachedURL),
           let decoded = try? decoder.decode(HorizonIndex.self, from: cachedData) {
            return sortProjects(decoded.projects)
        }

        guard let bundledURL = Bundle.main.url(forResource: "horizon-index", withExtension: "json"),
              let bundledData = try? Data(contentsOf: bundledURL),
              let decoded = try? decoder.decode(HorizonIndex.self, from: bundledData) else {
            return []
        }

        return sortProjects(decoded.projects)
    }

    func refreshFromRemote() async throws -> [HorizonProject] {
        let (data, response) = try await session.data(from: remoteIndexURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HorizonCatalogError.downloadFailed(http.statusCode)
        }

        let decoded = try decoder.decode(HorizonIndex.self, from: data)
        try? FileSystemManager.shared.saveCachedHorizonIndex(data)
        return sortProjects(decoded.projects)
    }

    func downloadLatest(for project: HorizonProject) async throws -> (fileName: String, data: Data, targetKind: ContentKind) {
        guard let latest = project.latestVersion,
              let url = URL(string: latest.file.url) else {
            throw HorizonCatalogError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HorizonCatalogError.downloadFailed(http.statusCode)
        }

        return (latest.file.name, data, project.targetContentKind)
    }

    private func sortProjects(_ projects: [HorizonProject]) -> [HorizonProject] {
        projects.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
    }
}
