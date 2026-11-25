import Foundation

enum ContentKind: String, CaseIterable, Identifiable, Codable {
    case mod
    case shader
    case resourcePack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mod: return "Моды"
        case .shader: return "Шейдеры"
        case .resourcePack: return "Ресурспаки"
        }
    }

    var folderName: String {
        switch self {
        case .mod: return "mods"
        case .shader: return "shaderpacks"
        case .resourcePack: return "resourcepacks"
        }
    }

    var modrinthProjectType: String {
        switch self {
        case .mod: return "mod"
        case .shader: return "shader"
        case .resourcePack: return "resourcepack"
        }
    }

    var systemImage: String {
        switch self {
        case .mod: return "puzzlepiece.extension"
        case .shader: return "sparkles"
        case .resourcePack: return "photo.stack"
        }
    }
}

struct ContentItem: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var fileName: String
    var kind: ContentKind
    var path: String
    var enabled: Bool
    var order: Int
    var sizeBytes: Int64
}

enum ShaderQuality: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high
    case ultra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .ultra: return "Ultra"
        }
    }
}

struct GraphicsSettings: Codable, Equatable {
    var renderDistance: Int = 12
    var maxFPS: Int = 60
    var vsync: Bool = true
    var metalFXUpscaling: Bool = true
    var shaderQuality: ShaderQuality = .medium
    var touchHUDScale: Double = 1.0
    var enableGamepad: Bool = true
}

struct PlayerProfile: Codable, Equatable {
    var username: String = "RustPlayer"
    var uuid: String = UUID().uuidString
    var offlineMode: Bool = true
}

struct GameInstance: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var minecraftVersion: String
    var engineBranch: String
    var customFlags: [String]
    var createdAt: Date
    var lastPlayedAt: Date?
    var mods: [ContentItem]
    var shaders: [ContentItem]
    var resourcePacks: [ContentItem]

    func items(for kind: ContentKind) -> [ContentItem] {
        switch kind {
        case .mod: return mods
        case .shader: return shaders
        case .resourcePack: return resourcePacks
        }
    }

    mutating func setItems(_ items: [ContentItem], for kind: ContentKind) {
        switch kind {
        case .mod: mods = items
        case .shader: shaders = items
        case .resourcePack: resourcePacks = items
        }
    }
}

enum EngineState: Int, Sendable {
    case idle = 0
    case validating = 1
    case loading = 2
    case running = 3
    case stopping = 4
    case error = 5

    var displayTitle: String {
        switch self {
        case .idle: return "Готов"
        case .validating: return "Проверка..."
        case .loading: return "Загрузка..."
        case .running: return "Запущен"
        case .stopping: return "Остановка..."
        case .error: return "Ошибка"
        }
    }
}

enum LogLevel: Int, Sendable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3

    var label: String {
        switch self {
        case .debug: return "DBG"
        case .info: return "INF"
        case .warn: return "WRN"
        case .error: return "ERR"
        }
    }
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

// MARK: - Rust FFI JSON Payloads

struct RustLaunchConfigPayload: Codable {
    let instanceId: String
    let instanceName: String
    let minecraftVersion: String
    let instanceRoot: String
    let account: RustAccountPayload
    let graphics: RustGraphicsPayload
    let mods: [RustContentDescriptorPayload]
    let shaders: [RustContentDescriptorPayload]
    let resourcePacks: [RustContentDescriptorPayload]
    let customFlags: [String]
}

struct RustAccountPayload: Codable {
    let username: String
    let uuid: String?
    let offlineMode: Bool
}

struct RustGraphicsPayload: Codable {
    let renderDistance: Int
    let maxFps: Int
    let vsync: Bool
    let metalfxUpscaling: Bool
    let shaderQuality: String
    let touchHudScale: Float
}

struct RustContentDescriptorPayload: Codable {
    let id: String
    let name: String
    let path: String
    let enabled: Bool
    let order: Int
}

struct RustValidationReport: Codable {
    let valid: Bool
    let errors: [String]
    let warnings: [String]
    let activeMods: Int?
    let activeShaders: Int?
    let activeResourcePacks: Int?
}

// MARK: - Modrinth API Models

struct ModrinthSearchResponse: Codable {
    let hits: [ModrinthProject]
    let totalHits: Int

    enum CodingKeys: String, CodingKey {
        case hits
        case totalHits = "total_hits"
    }
}

struct ModrinthProject: Identifiable, Codable, Hashable {
    let projectId: String
    let slug: String
    let title: String
    let description: String
    let author: String
    let downloads: Int
    let iconUrl: String?
    let projectType: String

    var id: String { projectId }

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case slug
        case title
        case description
        case author
        case downloads
        case iconUrl = "icon_url"
        case projectType = "project_type"
    }
}

struct ModrinthVersion: Identifiable, Codable {
    let id: String
    let name: String
    let versionNumber: String
    let files: [ModrinthFile]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case versionNumber = "version_number"
        case files
    }
}

struct ModrinthFile: Codable {
    let url: String
    let filename: String
    let primary: Bool
    let size: Int
}
