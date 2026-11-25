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
    @Published var showMissingGameFilesAlert = false

    @Published var navigationStack: [AppRoute] = [.home]
    @Published var horizonProjects: [HorizonProject] = []
    @Published var isLoadingCatalog = false
    @Published var installingProjectIDs: Set<String> = []
    @Published var importedGameFiles = ImportedGameFilesInfo()
    @Published var worldShortcuts: [WorldShortcut] = [
        WorldShortcut(title: "Новый мир", subtitle: "моя сборка", isServer: false),
        WorldShortcut(title: "Horizon Official", subtitle: "0/20 онлайн • моя сборка", isServer: true)
    ]

    private let fs = FileSystemManager.shared
    private let bridge = RustBridge.shared
    private let catalog = HorizonCatalogService.shared
    private let maxLogEntries = 400

    init() {
        self.graphicsSettings = fs.loadGraphicsSettings()
        self.profile = fs.loadProfile()
        loadOrCreateDefaultInstances()
        refreshImportedGameFiles()
        loadHorizonCatalog()
    }

    var currentRoute: AppRoute {
        navigationStack.last ?? .home
    }

    var canGoBack: Bool {
        navigationStack.count > 1
    }

    func navigate(to route: AppRoute) {
        if currentRoute == route { return }
        if route == .home {
            navigationStack = [.home]
        } else {
            navigationStack.append(route)
        }
    }

    func goBack() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
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

    func instance(for id: String) -> GameInstance? {
        instances.first(where: { $0.id == id })
    }

    var activeSkin: SkinPreset {
        SkinPreset.defaults.first(where: { $0.id == profile.selectedSkinID }) ?? SkinPreset.defaults[0]
    }

    var coreVersionText: String {
        bridge.coreVersion
    }

    var isNativeCoreLinked: Bool {
        bridge.isNativeCoreLinked
    }

    var totalPlayTimeMinutes: Int {
        instances.reduce(0) { $0 + $1.playTimeMinutes }
    }

    func loadOrCreateDefaultInstances() {
        do {
            try fs.ensureBaseDirectories()
        } catch {
            appendLog(.error, "Ошибка инициализации хранилища: \(error.localizedDescription)")
        }

        var loaded = fs.loadInstances()
        if loaded.isEmpty {
            let mainId = "horizon-my-pack"
            let rustId = "rust-horizon"
            try? fs.createInstanceDirectories(for: mainId)
            try? fs.createInstanceDirectories(for: rustId)

            loaded = [
                GameInstance(
                    id: mainId,
                    name: "моя сборка",
                    minecraftVersion: "26.3",
                    engineBranch: "Horizon",
                    customFlags: ["--metal-renderer"],
                    createdAt: Date().addingTimeInterval(-86400 * 3),
                    lastPlayedAt: Date().addingTimeInterval(-86400 * 3),
                    playTimeMinutes: 13,
                    badgeText: nil,
                    folderTag: nil,
                    mods: [],
                    shaders: [],
                    resourcePacks: []
                ),
                GameInstance(
                    id: rustId,
                    name: "Rust",
                    minecraftVersion: "Horizon",
                    engineBranch: "Rust",
                    customFlags: ["--metal-renderer"],
                    createdAt: Date().addingTimeInterval(-86400 * 5),
                    lastPlayedAt: Date().addingTimeInterval(-86400 * 3),
                    playTimeMinutes: 120,
                    badgeText: nil,
                    folderTag: nil,
                    mods: [],
                    shaders: [],
                    resourcePacks: []
                )
            ]
        }

        for index in loaded.indices {
            syncAllContent(for: &loaded[index])
        }

        instances = loaded
        selectedInstanceID = loaded.first?.id
        persistInstances()
        appendLog(.info, "Eternal Launcher инициализирован (Rust Core v\(bridge.coreVersion)).")
    }

    func loadHorizonCatalog() {
        let projects = catalog.loadBundledOrCached()
        horizonProjects = projects
        appendLog(.info, "Каталог Horizon загружен: \(projects.count) проектов.")
    }

    func refreshHorizonCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let updated = try await catalog.refreshFromRemote()
            horizonProjects = updated
            appendLog(.info, "Каталог Horizon обновлён онлайн: \(updated.count) проектов.")
        } catch {
            lastErrorMessage = "Не удалось обновить каталог онлайн: \(error.localizedDescription)"
        }
    }

    func isHorizonProjectInstalled(_ project: HorizonProject, in instance: GameInstance) -> Bool {
        let expectedFile = project.latestVersion?.file.name
        let list = instance.items(for: project.targetContentKind)
        return list.contains { item in
            item.horizonProjectID == project.id || (expectedFile != nil && item.fileName == expectedFile)
        }
    }

    func installHorizonProject(_ project: HorizonProject, into instanceID: String? = nil) async {
        let targetID = instanceID ?? activeInstance?.id
        guard let targetID,
              var targetInstance = instances.first(where: { $0.id == targetID }) else {
            return
        }

        installingProjectIDs.insert(project.id)
        defer { installingProjectIDs.remove(project.id) }

        do {
            appendLog(.info, "Загрузка '\(project.name)' из каталога Horizon...")
            let downloaded = try await catalog.downloadLatest(for: project)
            _ = try fs.saveDownloadedData(
                downloaded.data,
                fileName: downloaded.fileName,
                instanceId: targetInstance.id,
                kind: downloaded.targetKind
            )
            syncAllContent(for: &targetInstance)
            var list = targetInstance.items(for: downloaded.targetKind)
            if let idx = list.firstIndex(where: { $0.fileName == downloaded.fileName }) {
                list[idx].name = project.name
                list[idx].horizonProjectID = project.id
                targetInstance.setItems(list, for: downloaded.targetKind)
            }
            updateInstance(targetInstance)
            appendLog(.info, "Установлено '\(project.name)' (\(downloaded.fileName)).")
        } catch {
            lastErrorMessage = error.localizedDescription
            appendLog(.error, "Ошибка установки '\(project.name)': \(error.localizedDescription)")
        }
    }

    func refreshImportedGameFiles() {
        importedGameFiles = fs.inspectGameFiles()
    }

    func importGameFiles(urls: [URL]) {
        do {
            importedGameFiles = try fs.importGameFiles(from: urls)
            appendLog(
                .info,
                "Импортировано файлов игры: \(importedGameFiles.fileCount) (\(importedGameFiles.formattedSize))."
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            appendLog(.error, "Ошибка импорта файлов игры: \(error.localizedDescription)")
        }
    }

    func clearGameFiles() {
        do {
            try fs.clearGameFiles()
            refreshImportedGameFiles()
            appendLog(.info, "Импортированные файлы игры очищены.")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func importCustomSkin(urls: [URL]) {
        guard let first = urls.first else { return }
        do {
            let dest = try fs.importSkinFile(from: first)
            appendLog(.info, "Импортирован скин: \(dest.lastPathComponent)")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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

    private func updateInstance(_ updated: GameInstance) {
        if let idx = instances.firstIndex(where: { $0.id == updated.id }) {
            instances[idx] = updated
            persistInstances()
        }
    }

    func createInstance(name: String, minecraftVersion: String, engineBranch: String, flags: [String], folderTag: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let id = UUID().uuidString.lowercased()
        do {
            try fs.createInstanceDirectories(for: id)
            let instance = GameInstance(
                id: id,
                name: trimmedName,
                minecraftVersion: minecraftVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "26.3"
                    : minecraftVersion,
                engineBranch: engineBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Horizon"
                    : engineBranch,
                customFlags: flags,
                createdAt: Date(),
                lastPlayedAt: nil,
                playTimeMinutes: 0,
                badgeText: nil,
                folderTag: folderTag,
                mods: [],
                shaders: [],
                resourcePacks: []
            )
            instances.append(instance)
            selectedInstanceID = instance.id
            persistInstances()
            appendLog(.info, "Создана сборка '\(instance.name)' (\(instance.engineBranch) \(instance.minecraftVersion)).")
        } catch {
            lastErrorMessage = error.localizedDescription
            appendLog(.error, "Не удалось создать сборку: \(error.localizedDescription)")
        }
    }

    func deleteInstance(_ instance: GameInstance) {
        guard instances.count > 1 else {
            lastErrorMessage = "Нельзя удалить единственную сборку."
            return
        }
        try? fs.deleteInstanceDirectory(for: instance.id)
        instances.removeAll { $0.id == instance.id }
        if selectedInstanceID == instance.id {
            selectedInstanceID = instances.first?.id
        }
        persistInstances()
    }

    func toggleContentItem(_ item: ContentItem, in instanceID: String? = nil) {
        let id = instanceID ?? activeInstance?.id
        guard let id, var target = instance(for: id) else { return }
        var list = target.items(for: item.kind)
        guard let idx = list.firstIndex(where: { $0.id == item.id }) else { return }
        list[idx].enabled.toggle()
        target.setItems(list, for: item.kind)
        updateInstance(target)
    }

    func moveContentItems(kind: ContentKind, from source: IndexSet, to destination: Int, in instanceID: String? = nil) {
        let id = instanceID ?? activeInstance?.id
        guard let id, var target = instance(for: id) else { return }
        var list = target.items(for: kind)
        list.move(fromOffsets: source, toOffset: destination)
        for i in list.indices {
            list[i].order = i
        }
        target.setItems(list, for: kind)
        updateInstance(target)
    }

    func deleteContentItems(kind: ContentKind, at offsets: IndexSet, in instanceID: String? = nil) {
        let id = instanceID ?? activeInstance?.id
        guard let id, var target = instance(for: id) else { return }
        var list = target.items(for: kind)
        for index in offsets {
            try? fs.removeContentItem(list[index])
        }
        list.remove(atOffsets: offsets)
        for i in list.indices {
            list[i].order = i
        }
        target.setItems(list, for: kind)
        updateInstance(target)
    }

    func importLocalFiles(urls: [URL], kind: ContentKind, into instanceID: String? = nil) {
        let id = instanceID ?? activeInstance?.id
        guard let id, var target = instance(for: id) else { return }
        for url in urls {
            do {
                let dest = try fs.importContent(from: url, into: target.id, kind: kind)
                appendLog(.info, "Импортирован \(kind.title.lowercased()): \(dest.lastPathComponent)")
            } catch {
                lastErrorMessage = error.localizedDescription
                appendLog(.error, "Ошибка импорта \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        syncAllContent(for: &target)
        updateInstance(target)
    }

    func saveSettings() {
        try? fs.saveGraphicsSettings(graphicsSettings)
        try? fs.saveProfile(profile)
    }

    func instanceSizeFormatted(for instanceId: String) -> String {
        let bytes = fs.instanceSizeBytes(for: instanceId)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func buildLaunchPayload(for instance: GameInstance) -> RustLaunchConfigPayload {
        let rootPath = fs.instanceRootURL(for: instance.id).path
        return RustLaunchConfigPayload(
            instanceId: instance.id,
            instanceName: instance.name,
            minecraftVersion: instance.minecraftVersion,
            instanceRoot: rootPath,
            gameFilesRoot: fs.gameFilesDirectoryURL.path,
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

    func prepareAndOpenViewport(for instanceID: String? = nil) {
        if let instanceID {
            selectedInstanceID = instanceID
        }
        refreshImportedGameFiles()

        guard importedGameFiles.isImported else {
            showMissingGameFilesAlert = true
            return
        }

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
