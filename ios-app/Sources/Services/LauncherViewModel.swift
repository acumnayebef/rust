import Foundation
import QuartzCore
import SwiftUI

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var instances: [GameInstance] = []
    @Published var selectedInstanceID: String?
    @Published var graphicsSettings: GraphicsSettings
    @Published var profile: PlayerProfile
    @Published var engineState: EngineState = .idle
    @Published var logs: [LogEntry] = []
    @Published var isShowingViewport = false
    @Published var lastErrorMessage: String?

    private let fs = FileSystemManager.shared
    private let bridge = RustBridge.shared
    private let maxLogEntries = 400

    init() {
        self.graphicsSettings = fs.loadGraphicsSettings()
        self.profile = fs.loadProfile()
        loadOrCreateDefaultInstances()
    }

    var activeInstance: GameInstance? {
        get {
            guard let id = selectedInstanceID else { return instances.first }
            return instances.first(where: { $0.id == id }) ?? instances.first
        }
        set {
            guard let newValue,
                  let idx = instances.firstIndex(where: { $0.id == newValue.id }) else {
                return
            }
            instances[idx] = newValue
            persistInstances()
        }
    }

    var coreVersionText: String {
        bridge.coreVersion
    }

    var isNativeCoreLinked: Bool {
        bridge.isNativeCoreLinked
    }

    func loadOrCreateDefaultInstances() {
        do {
            try fs.ensureBaseDirectories()
        } catch {
            appendLog(.error, "Ошибка инициализации хранилища: \(error.localizedDescription)")
        }

        var loaded = fs.loadInstances()
        if loaded.isEmpty {
            let defaultId = "default-rust-1-21"
            try? fs.createInstanceDirectories(for: defaultId)
            let defaultInstance = GameInstance(
                id: defaultId,
                name: "Rust Client Default",
                minecraftVersion: "1.21.4",
                engineBranch: "custom-rust-main",
                customFlags: ["--metal-renderer"],
                createdAt: Date(),
                lastPlayedAt: nil,
                mods: [],
                shaders: [],
                resourcePacks: []
            )
            loaded = [defaultInstance]
        }

        for index in loaded.indices {
            syncAllContent(for: &loaded[index])
        }

        instances = loaded
        selectedInstanceID = loaded.first?.id
        persistInstances()
        appendLog(.info, "Лаунчер инициализирован (Rust Core v\(bridge.coreVersion)).")
    }

    func refreshActiveInstanceContent() {
        guard var current = activeInstance else { return }
        syncAllContent(for: &current)
        activeInstance = current
    }

    private func syncAllContent(for instance: inout GameInstance) {
        for kind in ContentKind.allCases {
            try? fs.syncContent(for: &instance, kind: kind)
        }
    }

    func createInstance(name: String, minecraftVersion: String, engineBranch: String, flags: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let id = UUID().uuidString.lowercased()
        do {
            try fs.createInstanceDirectories(for: id)
            let instance = GameInstance(
                id: id,
                name: trimmedName,
                minecraftVersion: minecraftVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "1.21.4"
                    : minecraftVersion,
                engineBranch: engineBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "custom-rust-main"
                    : engineBranch,
                customFlags: flags,
                createdAt: Date(),
                lastPlayedAt: nil,
                mods: [],
                shaders: [],
                resourcePacks: []
            )
            instances.append(instance)
            selectedInstanceID = instance.id
            persistInstances()
            appendLog(.info, "Создан профиль '\(instance.name)' (MC \(instance.minecraftVersion)).")
        } catch {
            lastErrorMessage = error.localizedDescription
            appendLog(.error, "Не удалось создать профиль: \(error.localizedDescription)")
        }
    }

    func deleteInstance(_ instance: GameInstance) {
        guard instances.count > 1 else {
            lastErrorMessage = "Нельзя удалить единственный профиль."
            return
        }
        try? fs.deleteInstanceDirectory(for: instance.id)
        instances.removeAll { $0.id == instance.id }
        if selectedInstanceID == instance.id {
            selectedInstanceID = instances.first?.id
        }
        persistInstances()
    }

    func toggleContentItem(_ item: ContentItem) {
        guard var current = activeInstance else { return }
        var list = current.items(for: item.kind)
        guard let idx = list.firstIndex(where: { $0.id == item.id }) else { return }
        list[idx].enabled.toggle()
        current.setItems(list, for: item.kind)
        activeInstance = current
    }

    func moveContentItems(kind: ContentKind, from source: IndexSet, to destination: Int) {
        guard var current = activeInstance else { return }
        var list = current.items(for: kind)
        list.move(fromOffsets: source, toOffset: destination)
        for i in list.indices {
            list[i].order = i
        }
        current.setItems(list, for: kind)
        activeInstance = current
    }

    func deleteContentItems(kind: ContentKind, at offsets: IndexSet) {
        guard var current = activeInstance else { return }
        var list = current.items(for: kind)
        for index in offsets {
            try? fs.removeContentItem(list[index])
        }
        list.remove(atOffsets: offsets)
        for i in list.indices {
            list[i].order = i
        }
        current.setItems(list, for: kind)
        activeInstance = current
    }

    func importLocalFiles(urls: [URL], kind: ContentKind) {
        guard var current = activeInstance else { return }
        for url in urls {
            do {
                let dest = try fs.importContent(from: url, into: current.id, kind: kind)
                appendLog(.info, "Импортирован \(kind.title.lowercased()): \(dest.lastPathComponent)")
            } catch {
                lastErrorMessage = error.localizedDescription
                appendLog(.error, "Ошибка импорта \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        syncAllContent(for: &current)
        activeInstance = current
    }

    func installFromModrinth(project: ModrinthProject, kind: ContentKind) async throws {
        guard var current = activeInstance else { return }
        appendLog(.info, "Загрузка '\(project.title)' с Modrinth...")
        let downloaded = try await ModrinthClient.shared.downloadLatestFile(projectId: project.projectId)
        let savedURL = try fs.saveDownloadedData(
            downloaded.data,
            fileName: downloaded.fileName,
            instanceId: current.id,
            kind: kind
        )
        syncAllContent(for: &current)
        activeInstance = current
        appendLog(.info, "Установлено в \(kind.folderName): \(savedURL.lastPathComponent)")
    }

    func saveSettings() {
        try? fs.saveGraphicsSettings(graphicsSettings)
        try? fs.saveProfile(profile)
    }

    func buildLaunchPayload(for instance: GameInstance) -> RustLaunchConfigPayload {
        let rootPath = fs.instanceRootURL(for: instance.id).path
        return RustLaunchConfigPayload(
            instanceId: instance.id,
            instanceName: instance.name,
            minecraftVersion: instance.minecraftVersion,
            instanceRoot: rootPath,
            account: RustAccountPayload(
                username: profile.username,
                uuid: profile.uuid,
                offlineMode: profile.offlineMode
            ),
            graphics: RustGraphicsPayload(
                renderDistance: graphicsSettings.renderDistance,
                maxFps: graphicsSettings.maxFPS,
                vsync: graphicsSettings.vsync,
                metalfxUpscaling: graphicsSettings.metalFXUpscaling,
                shaderQuality: graphicsSettings.shaderQuality.rawValue,
                touchHudScale: Float(graphicsSettings.touchHUDScale)
            ),
            mods: instance.mods.map {
                RustContentDescriptorPayload(
                    id: $0.id,
                    name: $0.name,
                    path: $0.path,
                    enabled: $0.enabled,
                    order: $0.order
                )
            },
            shaders: instance.shaders.map {
                RustContentDescriptorPayload(
                    id: $0.id,
                    name: $0.name,
                    path: $0.path,
                    enabled: $0.enabled,
                    order: $0.order
                )
            },
            resourcePacks: instance.resourcePacks.map {
                RustContentDescriptorPayload(
                    id: $0.id,
                    name: $0.name,
                    path: $0.path,
                    enabled: $0.enabled,
                    order: $0.order
                )
            },
            customFlags: instance.customFlags
        )
    }

    func prepareAndOpenViewport() {
        guard var current = activeInstance else { return }
        syncAllContent(for: &current)
        activeInstance = current

        let payload = buildLaunchPayload(for: current)
        let report = bridge.validateConfig(payload)

        for warning in report.warnings {
            appendLog(.warn, warning)
        }
        if !report.valid {
            let joined = report.errors.joined(separator: "\n")
            lastErrorMessage = joined
            for error in report.errors {
                appendLog(.error, error)
            }
            engineState = .error
            return
        }

        isShowingViewport = true
    }

    func startEngine(metalLayer: CAMetalLayer) {
        guard var current = activeInstance else { return }
        let payload = buildLaunchPayload(for: current)

        engineState = .loading
        let code = bridge.start(payload: payload, metalLayer: metalLayer) { [weak self] level, message in
            Task { @MainActor in
                self?.appendLog(level, message)
            }
        }

        if code == 0 {
            engineState = bridge.isNativeCoreLinked ? bridge.currentStatus() : .running
            current.lastPlayedAt = Date()
            activeInstance = current
        } else {
            engineState = .error
            lastErrorMessage = "Rust-ядро завершило запуск с кодом \(code)."
            appendLog(.error, "Код ошибки запуска Rust-ядра: \(code)")
        }
    }

    func stopEngine() {
        _ = bridge.stop()
        engineState = .idle
        isShowingViewport = false
        appendLog(.info, "Игровая сессия остановлена.")
    }

    func resizeViewport(width: UInt32, height: UInt32, scale: Float) {
        bridge.resize(width: width, height: height, scale: scale)
    }

    func sendTouchInput(action: Int32, x: Float, y: Float, dx: Float = 0, dy: Float = 0) {
        bridge.sendTouchInput(action: action, x: x, y: y, dx: dx, dy: dy)
    }

    func clearLogs() {
        logs.removeAll()
    }

    func appendLog(_ level: LogLevel, _ message: String) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
    }

    private func persistInstances() {
        try? fs.saveInstances(instances)
    }
}
