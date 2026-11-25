import SwiftUI
import UniformTypeIdentifiers

enum InstanceSubTab: String, CaseIterable, Identifiable {
    case mods = "Моды"
    case files = "Файлы"
    case worlds = "Миры"
    case servers = "Сервера"
    case logs = "Журнал"

    var id: String { rawValue }
}

struct ContentManagerView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel

    let instanceID: String?
    @State private var activeTab: InstanceSubTab
    @State private var installedFilterText = ""
    @State private var catalogSearchText = ""
    @State private var selectedCategory: HorizonCategoryFilter = .all
    @State private var selectedFileKind: ContentKind = .mod
    @State private var isImporterPresented = false

    init(instanceID: String?, initialTab: InstanceSubTab = .mods) {
        self.instanceID = instanceID
        _activeTab = State(initialValue: initialTab)
    }

    private var instance: GameInstance? {
        if let instanceID, let found = viewModel.instance(for: instanceID) {
            return found
        }
        return viewModel.activeInstance
    }

    private var filteredHorizonProjects: [HorizonProject] {
        let query = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.horizonProjects.filter { project in
            guard selectedCategory.matches(project) else { return false }
            if query.isEmpty { return true }
            return project.name.lowercased().contains(query)
                || (project.summary?.lowercased().contains(query) ?? false)
                || project.primaryAuthor.lowercased().contains(query)
                || project.id.lowercased().contains(query)
        }
    }

    private var allowedContentTypes: [UTType] {
        var types: [UTType] = [.zip, .archive, .folder, .data, .item]
        for ext in ["hmod", "hnmod", "wasm", "dylib"] {
            if let custom = UTType(filenameExtension: ext) {
                types.append(custom)
            }
        }
        return types
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let instance {
                    heroHeader(for: instance)
                    subTabsRow
                    switch activeTab {
                    case .mods:
                        horizonCatalogSection(for: instance)
                    case .files:
                        installedFilesSection(for: instance)
                    case .worlds:
                        worldsSection
                    case .servers:
                        serversSection
                    case .logs:
                        logsSection
                    }
                }
            }
            .padding(20)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.importLocalFiles(urls: urls, kind: selectedFileKind, into: instance?.id)
            }
        }
    }

    private func heroHeader(for instance: GameInstance) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                heroInfo(for: instance)
                Spacer()
                heroActions(for: instance)
            }
            .padding(16)
            .eternalCard(cornerRadius: 16)

            VStack(alignment: .leading, spacing: 12) {
                heroInfo(for: instance)
                heroActions(for: instance)
            }
            .padding(16)
            .eternalCard(cornerRadius: 16)
        }
    }

    private func heroInfo(for instance: GameInstance) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "cube")
                        .font(.title2)
                        .foregroundStyle(EternalPalette.textSecondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(instance.name)
                    .font(.title3.bold())
                    .foregroundStyle(EternalPalette.textPrimary)
                Text("\(instance.engineBranch) \(instance.minecraftVersion) • \(instance.playTimeMinutes) минут")
                    .font(.caption)
                    .foregroundStyle(EternalPalette.textSecondary)
                Text("Вес: \(viewModel.instanceSizeFormatted(for: instance.id)) • Модов: \(instance.mods.count)")
                    .font(.caption2)
                    .foregroundStyle(EternalPalette.textMuted)
            }
        }
    }

    private func heroActions(for instance: GameInstance) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.prepareAndOpenViewport(for: instance.id)
            } label: {
                Label("Играть", systemImage: "play.fill")
                    .font(.caption.bold())
                    .foregroundStyle(EternalPalette.roseInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(EternalPalette.rose, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.navigate(to: .settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(EternalPalette.textSecondary)
                    .frame(width: 36, height: 36)
                    .eternalCard(cornerRadius: 10)
            }

            Menu {
                Button("Обновить файлы") {
                    viewModel.refreshActiveInstanceContent()
                }
                if viewModel.instances.count > 1 {
                    Button("Удалить сборку", role: .destructive) {
                        viewModel.deleteInstance(instance)
                        viewModel.navigate(to: .library)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(EternalPalette.textSecondary)
                    .frame(width: 36, height: 36)
                    .eternalCard(cornerRadius: 10)
            }
        }
    }

    private var subTabsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InstanceSubTab.allCases) { tab in
                    let active = activeTab == tab
                    Button {
                        activeTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(active ? EternalPalette.roseInk : EternalPalette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(active ? EternalPalette.rose : EternalPalette.cardFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func horizonCatalogSection(for instance: GameInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(EternalPalette.textMuted)
                    TextField("Фильтр установленных (\(instance.totalContentCount))...", text: $installedFilterText)
                        .font(.caption)
                        .foregroundStyle(EternalPalette.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .eternalCard(cornerRadius: 10)

                Button {
                    selectedFileKind = .mod
                    isImporterPresented = true
                } label: {
                    Label("Добавить файлы", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(EternalPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .eternalCard(cornerRadius: 10)
                }

                Button {
                    activeTab = .files
                } label: {
                    Label("К установленным", systemImage: "list.bullet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(EternalPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .eternalCard(cornerRadius: 10)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(EternalPalette.textMuted)
                    TextField("Поиск в каталоге Horizon...", text: $catalogSearchText)
                        .font(.caption)
                        .foregroundStyle(EternalPalette.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .eternalCard(cornerRadius: 10)

                Button {
                    Task { await viewModel.refreshHorizonCatalog() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isLoadingCatalog {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Обновить")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EternalPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .eternalCard(cornerRadius: 10)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HorizonCategoryFilter.allCases) { category in
                        let active = selectedCategory == category
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.title)
                                .font(.caption.bold())
                                .foregroundStyle(active ? EternalPalette.roseInk : EternalPalette.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(active ? EternalPalette.rose : EternalPalette.cardFill)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LazyVStack(spacing: 8) {
                ForEach(filteredHorizonProjects) { project in
                    horizonProjectRow(project, instance: instance)
                }
            }
        }
    }

    private func horizonProjectRow(_ project: HorizonProject, instance: GameInstance) -> some View {
        let installed = viewModel.isHorizonProjectInstalled(project, in: instance)
        let isInstalling = viewModel.installingProjectIDs.contains(project.id)

        return HStack(spacing: 12) {
            AsyncImage(url: project.icon.flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            Image(systemName: project.targetContentKind.systemImage)
                                .foregroundStyle(EternalPalette.textSecondary)
                        }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(EternalPalette.textPrimary)
                    .lineLimit(1)

                Text(
                    "\(project.displayKindTitle) • \(project.primaryAuthor) • \(project.latestVersion?.version ?? "1.0") • \(project.downloads ?? 0) загрузок"
                )
                .font(.caption2)
                .foregroundStyle(EternalPalette.textMuted)
                .lineLimit(1)

                if let summary = project.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(EternalPalette.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if isInstalling {
                ProgressView()
                    .tint(EternalPalette.rose)
                    .frame(width: 96)
            } else if installed {
                Text("Установлен")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EternalPalette.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Button {
                    Task {
                        await viewModel.installHorizonProject(project, into: instance.id)
                    }
                } label: {
                    Label("Установить", systemImage: "arrow.down.to.line")
                        .font(.caption.bold())
                        .foregroundStyle(EternalPalette.roseInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(EternalPalette.rose, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .eternalCard(cornerRadius: 12)
    }

    private func installedFilesSection(for instance: GameInstance) -> some View {
        let query = installedFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawItems = instance.items(for: selectedFileKind)
        let items = query.isEmpty ? rawItems : rawItems.filter { $0.name.lowercased().contains(query) || $0.fileName.lowercased().contains(query) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ContentKind.allCases) { kind in
                    let active = selectedFileKind == kind
                    Button {
                        selectedFileKind = kind
                    } label: {
                        Text("\(kind.title) (\(instance.items(for: kind).count))")
                            .font(.caption.bold())
                            .foregroundStyle(active ? EternalPalette.roseInk : EternalPalette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(active ? EternalPalette.rose : EternalPalette.cardFill)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Добавить файлы", systemImage: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(EternalPalette.roseInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(EternalPalette.rose, in: RoundedRectangle(cornerRadius: 9))
                }
            }

            if items.isEmpty {
                Text("Нет установленных файлов в папке \(selectedFileKind.folderName)/.")
                    .font(.subheadline)
                    .foregroundStyle(EternalPalette.textSecondary)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .eternalCard(cornerRadius: 12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: selectedFileKind.systemImage)
                                .foregroundStyle(item.enabled ? EternalPalette.rose : EternalPalette.textMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(EternalPalette.textPrimary)
                                Text(item.fileName)
                                    .font(.caption2)
                                    .foregroundStyle(EternalPalette.textMuted)
                            }
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { item.enabled },
                                    set: { _ in viewModel.toggleContentItem(item, in: instance.id) }
                                )
                            )
                            .labelsHidden()
                            .tint(EternalPalette.rose)

                            Button(role: .destructive) {
                                if let idx = rawItems.firstIndex(where: { $0.id == item.id }) {
                                    viewModel.deleteContentItems(kind: selectedFileKind, at: IndexSet(integer: idx), in: instance.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                        }
                        .padding(12)
                        .eternalCard(cornerRadius: 12)
                    }
                }
            }
        }
    }

    private var worldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.worldShortcuts.filter { !$0.isServer }) { world in
                HStack {
                    Image(systemName: "globe.europe.africa.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(world.title).font(.subheadline.bold()).foregroundStyle(EternalPalette.textPrimary)
                        Text(world.subtitle).font(.caption2).foregroundStyle(EternalPalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .eternalCard(cornerRadius: 12)
            }
        }
    }

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.worldShortcuts.filter { $0.isServer }) { server in
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(EternalPalette.rose)
                    VStack(alignment: .leading) {
                        Text(server.title).font(.subheadline.bold()).foregroundStyle(EternalPalette.textPrimary)
                        Text(server.subtitle).font(.caption2).foregroundStyle(EternalPalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .eternalCard(cornerRadius: 12)
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Журнал Rust Core (\(viewModel.logs.count))")
                    .font(.subheadline.bold())
                    .foregroundStyle(EternalPalette.textPrimary)
                Spacer()
                Button("Очистить") {
                    viewModel.clearLogs()
                }
                .font(.caption)
                .foregroundStyle(EternalPalette.rose)
            }

            if viewModel.logs.isEmpty {
                Text("Логи появятся после запуска импортированной игры.")
                    .font(.caption)
                    .foregroundStyle(EternalPalette.textSecondary)
                    .padding(12)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.logs.suffix(80)) { entry in
                        Text("[\(entry.level.label)] \(entry.message)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(entry.level == .error ? .red : EternalPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .eternalCard(cornerRadius: 14)
    }
}
