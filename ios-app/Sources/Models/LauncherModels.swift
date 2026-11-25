import Foundation
import SwiftUI

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
    var horizonProjectID: String?
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
    var username: String = "xantapers"
    var uuid: String = UUID().uuidString
    var offlineMode: Bool = true
    var selectedSkinID: String = "steve"
    var selectedParticle: ParticleOption = .none
    var selectedCapeName: String = "Без плаща"
}

struct GameInstance: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var minecraftVersion: String
    var engineBranch: String
    var customFlags: [String]
    var createdAt: Date
    var lastPlayedAt: Date?
    var playTimeMinutes: Int
    var badgeText: String?
    var folderTag: String?
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

    var totalContentCount: Int {
        mods.count + shaders.count + resourcePacks.count
    }
}

struct ImportedGameFilesInfo: Equatable {
    var fileCount: Int = 0
    var totalBytes: Int64 = 0
    var detectedEntrypoint: String?
    var rootPath: String = ""

    var isImported: Bool {
        fileCount > 0
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
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
        case .idle: return "Нет запущенных сборок"
        case .validating: return "Проверка файлов..."
        case .loading: return "Запуск игры..."
        case .running: return "Игра запущена"
        case .stopping: return "Остановка..."
        case .error: return "Ошибка запуска"
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
    let gameFilesRoot: String
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

// MARK: - Horizon Catalog Models (horizon-index.json)

struct HorizonIndex: Codable {
    let schema: Int?
    let generated: String?
    let projects: [HorizonProject]
}

struct HorizonProject: Identifiable, Codable, Hashable {
    let id: String
    let kind: String
    let name: String
    let summary: String?
    let description: String?
    let authors: [String]?
    let owners: [String]?
    let license: String?
    let source: String?
    let icon: String?
    let categories: [String]?
    let tags: [String]?
    let screenshots: [String]?
    let versions: [HorizonVersion]
    let downloads: Int?

    var primaryAuthor: String {
        authors?.first ?? owners?.first ?? "Horizon"
    }

    var latestVersion: HorizonVersion? {
        versions.first
    }

    var displayKindTitle: String {
        switch kind {
        case "native-mod": return "Нативный мод"
        case "mod": return "Мод"
        case "shader": return "Шейдер"
        case "resourcepack": return "Ресурспак"
        case "datapack": return "Датапак"
        default: return kind
        }
    }

    var targetContentKind: ContentKind {
        switch kind {
        case "shader": return .shader
        case "resourcepack": return .resourcePack
        default: return .mod
        }
    }
}

struct HorizonVersion: Codable, Hashable {
    let version: String
    let published: String?
    let changelog: String?
    let api: String?
    let game: String?
    let side: String?
    let capabilities: [String]?
    let file: HorizonFile
}

struct HorizonFile: Codable, Hashable {
    let name: String
    let url: String
    let size: Int64?
    let sha256: String?
}

enum HorizonCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case mod
    case nativeMod
    case shader
    case resourcePack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Всё"
        case .mod: return "Моды"
        case .nativeMod: return "Нативные"
        case .shader: return "Шейдеры"
        case .resourcePack: return "Ресурспаки"
        }
    }

    func matches(_ project: HorizonProject) -> Bool {
        switch self {
        case .all: return true
        case .mod: return project.kind == "mod" || project.kind == "datapack"
        case .nativeMod: return project.kind == "native-mod"
        case .shader: return project.kind == "shader"
        case .resourcePack: return project.kind == "resourcepack"
        }
    }
}

// MARK: - Eternal Launcher UI Models

enum AppRoute: Equatable, Hashable {
    case home
    case catalog
    case library
    case skins
    case screenshots
    case stats
    case settings
    case instanceDetail(String)

    var title: String {
        switch self {
        case .home: return "Главная"
        case .catalog: return "Моды и сборки"
        case .library: return "Библиотека"
        case .skins: return "Скины"
        case .screenshots: return "Скриншоты"
        case .stats: return "Статистика"
        case .settings: return "Настройки"
        case .instanceDetail: return "Сборка"
        }
    }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case name
    case lastPlayed
    case createdAt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Название"
        case .lastPlayed: return "Последний запуск"
        case .createdAt: return "Дата создания"
        }
    }
}

enum SkinModelKind: String, Codable {
    case classic = "CLASSIC"
    case slim = "SLIM"
}

enum ParticleOption: String, CaseIterable, Identifiable, Codable {
    case none
    case hearts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Без частиц"
        case .hearts: return "Сердечки"
        }
    }
}

struct SkinPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let modelKind: SkinModelKind
    let skinTone: Color
    let hairColor: Color
    let shirtColor: Color
    let pantsColor: Color
    let eyeColor: Color
    let accentColor: Color

    static let defaults: [SkinPreset] = [
        SkinPreset(
            id: "steve",
            name: "Steve",
            modelKind: .classic,
            skinTone: Color(red: 0.78, green: 0.56, blue: 0.42),
            hairColor: Color(red: 0.25, green: 0.16, blue: 0.10),
            shirtColor: Color(red: 0.04, green: 0.65, blue: 0.68),
            pantsColor: Color(red: 0.24, green: 0.24, blue: 0.68),
            eyeColor: Color(red: 0.34, green: 0.24, blue: 0.65),
            accentColor: Color(red: 0.03, green: 0.48, blue: 0.51)
        ),
        SkinPreset(
            id: "alex",
            name: "Alex",
            modelKind: .slim,
            skinTone: Color(red: 0.94, green: 0.76, blue: 0.62),
            hairColor: Color(red: 0.84, green: 0.45, blue: 0.18),
            shirtColor: Color(red: 0.42, green: 0.62, blue: 0.25),
            pantsColor: Color(red: 0.36, green: 0.26, blue: 0.18),
            eyeColor: Color(red: 0.22, green: 0.52, blue: 0.20),
            accentColor: Color(red: 0.68, green: 0.68, blue: 0.68)
        ),
        SkinPreset(
            id: "ari",
            name: "Ari",
            modelKind: .classic,
            skinTone: Color(red: 0.87, green: 0.65, blue: 0.50),
            hairColor: Color(red: 0.65, green: 0.30, blue: 0.15),
            shirtColor: Color(red: 0.93, green: 0.65, blue: 0.22),
            pantsColor: Color(red: 0.25, green: 0.22, blue: 0.26),
            eyeColor: Color(red: 0.25, green: 0.20, blue: 0.18),
            accentColor: Color(red: 0.82, green: 0.48, blue: 0.16)
        ),
        SkinPreset(
            id: "efe",
            name: "Efe",
            modelKind: .slim,
            skinTone: Color(red: 0.72, green: 0.51, blue: 0.40),
            hairColor: Color(red: 0.45, green: 0.28, blue: 0.66),
            shirtColor: Color(red: 0.22, green: 0.32, blue: 0.62),
            pantsColor: Color(red: 0.18, green: 0.18, blue: 0.30),
            eyeColor: Color(red: 0.34, green: 0.22, blue: 0.50),
            accentColor: Color(red: 0.86, green: 0.72, blue: 0.30)
        ),
        SkinPreset(
            id: "kai",
            name: "Kai",
            modelKind: .classic,
            skinTone: Color(red: 0.93, green: 0.75, blue: 0.60),
            hairColor: Color(red: 0.92, green: 0.79, blue: 0.42),
            shirtColor: Color(red: 0.32, green: 0.18, blue: 0.36),
            pantsColor: Color(red: 0.18, green: 0.14, blue: 0.24),
            eyeColor: Color(red: 0.24, green: 0.20, blue: 0.30),
            accentColor: Color(red: 0.68, green: 0.38, blue: 0.65)
        ),
        SkinPreset(
            id: "makena",
            name: "Makena",
            modelKind: .slim,
            skinTone: Color(red: 0.45, green: 0.30, blue: 0.22),
            hairColor: Color(red: 0.14, green: 0.10, blue: 0.10),
            shirtColor: Color(red: 0.88, green: 0.68, blue: 0.18),
            pantsColor: Color(red: 0.78, green: 0.28, blue: 0.24),
            eyeColor: Color(red: 0.18, green: 0.12, blue: 0.10),
            accentColor: Color(red: 0.92, green: 0.54, blue: 0.20)
        )
    ]
}

struct WorldShortcut: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let isServer: Bool
}
