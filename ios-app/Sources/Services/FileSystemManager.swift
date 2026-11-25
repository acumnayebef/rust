import Foundation

enum FileSystemError: LocalizedError {
    case securityScopeDenied
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .securityScopeDenied:
            return "Не удалось получить доступ к выбранному файлу."
        case .invalidDestination:
            return "Неверный путь назначения в хранилище лаунчера."
        }
    }
}

final class FileSystemManager {
    static let shared = FileSystemManager()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    var launcherRootURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("MCRustLauncher", isDirectory: true)
    }

    var instancesDirectoryURL: URL {
        launcherRootURL.appendingPathComponent("instances", isDirectory: true)
    }

    var gameFilesDirectoryURL: URL {
        launcherRootURL.appendingPathComponent("game-files", isDirectory: true)
    }

    var skinsDirectoryURL: URL {
        launcherRootURL.appendingPathComponent("skins", isDirectory: true)
    }

    var screenshotsDirectoryURL: URL {
        launcherRootURL.appendingPathComponent("screenshots", isDirectory: true)
    }

    var cachedHorizonIndexURL: URL {
        launcherRootURL.appendingPathComponent("horizon-index-cache.json")
    }

    var instancesMetadataURL: URL {
        launcherRootURL.appendingPathComponent("instances.json")
    }

    var settingsURL: URL {
        launcherRootURL.appendingPathComponent("settings.json")
    }

    var profileURL: URL {
        launcherRootURL.appendingPathComponent("profile.json")
    }

    func ensureBaseDirectories() throws {
        try fileManager.createDirectory(at: launcherRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: instancesDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: gameFilesDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: skinsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: screenshotsDirectoryURL, withIntermediateDirectories: true)
    }

    func instanceRootURL(for instanceId: String) -> URL {
        instancesDirectoryURL.appendingPathComponent(instanceId, isDirectory: true)
    }

    func contentFolderURL(for instanceId: String, kind: ContentKind) -> URL {
        instanceRootURL(for: instanceId).appendingPathComponent(kind.folderName, isDirectory: true)
    }

    func createInstanceDirectories(for instanceId: String) throws {
        let root = instanceRootURL(for: instanceId)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for subfolder in ["mods", "shaderpacks", "resourcepacks", "saves", "logs"] {
            let dir = root.appendingPathComponent(subfolder, isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func deleteInstanceDirectory(for instanceId: String) throws {
        let root = instanceRootURL(for: instanceId)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    func saveCachedHorizonIndex(_ data: Data) throws {
        try ensureBaseDirectories()
        try data.write(to: cachedHorizonIndexURL, options: .atomic)
    }

    func loadInstances() -> [GameInstance] {
        guard let data = try? Data(contentsOf: instancesMetadataURL),
              let loaded = try? decoder.decode([GameInstance].self, from: data) else {
            return []
        }
        return loaded
    }

    func saveInstances(_ instances: [GameInstance]) throws {
        try ensureBaseDirectories()
        let data = try encoder.encode(instances)
        try data.write(to: instancesMetadataURL, options: .atomic)
    }

    func loadGraphicsSettings() -> GraphicsSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(GraphicsSettings.self, from: data) else {
            return GraphicsSettings()
        }
        return settings
    }

    func saveGraphicsSettings(_ settings: GraphicsSettings) throws {
        try ensureBaseDirectories()
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    func loadProfile() -> PlayerProfile {
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? decoder.decode(PlayerProfile.self, from: data) else {
            return PlayerProfile()
        }
        return profile
    }

    func saveProfile(_ profile: PlayerProfile) throws {
        try ensureBaseDirectories()
        let data = try encoder.encode(profile)
        try data.write(to: profileURL, options: .atomic)
    }

    // MARK: - Game Files Import & Inspection

    func importGameFiles(from sourceURLs: [URL]) throws -> ImportedGameFilesInfo {
        try ensureBaseDirectories()
        for sourceURL in sourceURLs {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destURL = gameFilesDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
        }
        return inspectGameFiles()
    }

    func inspectGameFiles() -> ImportedGameFilesInfo {
        try? ensureBaseDirectories()
        var info = ImportedGameFilesInfo(rootPath: gameFilesDirectoryURL.path)

        guard let enumerator = fileManager.enumerator(
            at: gameFilesDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return info
        }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            info.fileCount += 1
            info.totalBytes += Int64(values?.fileSize ?? 0)

            let ext = fileURL.pathExtension.lowercased()
            if info.detectedEntrypoint == nil && (ext == "dylib" || ext == "wasm" || ext == "ipa" || ext == "zip") {
                info.detectedEntrypoint = fileURL.lastPathComponent
            }
        }
        return info
    }

    func clearGameFiles() throws {
        if fileManager.fileExists(atPath: gameFilesDirectoryURL.path) {
            try fileManager.removeItem(at: gameFilesDirectoryURL)
        }
        try fileManager.createDirectory(at: gameFilesDirectoryURL, withIntermediateDirectories: true)
    }

    func importSkinFile(from sourceURL: URL) throws -> URL {
        try ensureBaseDirectories()
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let destURL = skinsDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    // MARK: - Instance Content Management

    func syncContent(for instance: inout GameInstance, kind: ContentKind) throws {
        try createInstanceDirectories(for: instance.id)
        let folder = contentFolderURL(for: instance.id, kind: kind)
        let entries = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let existing = instance.items(for: kind)
        var existingByFileName: [String: ContentItem] = [:]
        for item in existing {
            existingByFileName[item.fileName] = item
        }

        var synced: [ContentItem] = []
        for (index, url) in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).enumerated() {
            let fileName = url.lastPathComponent
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            let sizeBytes = Int64(resourceValues?.fileSize ?? 0)

            if var old = existingByFileName[fileName] {
                old.path = url.path
                old.sizeBytes = sizeBytes
                synced.append(old)
            } else {
                let displayName = url.deletingPathExtension().lastPathComponent
                synced.append(
                    ContentItem(
                        id: UUID().uuidString,
                        name: displayName,
                        fileName: fileName,
                        kind: kind,
                        path: url.path,
                        enabled: true,
                        order: existing.count + index,
                        sizeBytes: sizeBytes,
                        horizonProjectID: nil
                    )
                )
            }
        }

        synced.sort { $0.order < $1.order }
        for i in synced.indices {
            synced[i].order = i
        }
        instance.setItems(synced, for: kind)
    }

    func importContent(from sourceURL: URL, into instanceId: String, kind: ContentKind) throws -> URL {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try createInstanceDirectories(for: instanceId)
        let destFolder = contentFolderURL(for: instanceId, kind: kind)
        let destURL = destFolder.appendingPathComponent(sourceURL.lastPathComponent)

        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    func saveDownloadedData(_ data: Data, fileName: String, instanceId: String, kind: ContentKind) throws -> URL {
        try createInstanceDirectories(for: instanceId)
        let destFolder = contentFolderURL(for: instanceId, kind: kind)
        let destURL = destFolder.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try data.write(to: destURL, options: .atomic)
        return destURL
    }

    func removeContentItem(_ item: ContentItem) throws {
        let url = URL(fileURLWithPath: item.path)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func instanceSizeBytes(for instanceId: String) -> Int64 {
        let root = instanceRootURL(for: instanceId)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if vals?.isRegularFile == true {
                total += Int64(vals?.fileSize ?? 0)
            }
        }
        return total
    }
}
