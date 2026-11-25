import SwiftUI
import UniformTypeIdentifiers

struct InstancesView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @State private var searchText = ""
    @State private var sortOption: LibrarySortOption = .name
    @State private var isCreateSheetPresented = false
    @State private var isFolderAlertPresented = false
    @State private var newFolderName = ""
    @State private var isImporterPresented = false

    private var filteredInstances: [GameInstance] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = viewModel.instances.filter { instance in
            query.isEmpty
                || instance.name.lowercased().contains(query)
                || instance.minecraftVersion.lowercased().contains(query)
                || (instance.folderTag?.lowercased().contains(query) ?? false)
        }

        switch sortOption {
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastPlayed:
            return filtered.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .createdAt:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                searchAndSortRow
                instancesGrid
            }
            .padding(20)
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateInstanceSheet { name, mcVersion, branch, flags, folder in
                viewModel.createInstance(
                    name: name,
                    minecraftVersion: mcVersion,
                    engineBranch: branch,
                    flags: flags,
                    folderTag: folder
                )
            }
        }
        .alert("Новая папка", isPresented: $isFolderAlertPresented) {
            TextField("Название папки", text: $newFolderName)
            Button("ОК") {
                if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                    viewModel.appendLog(.info, "Папка '\(newFolderName)' добавлена в библиотеку.")
                    newFolderName = ""
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder, .zip, .archive, .data, .item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.importGameFiles(urls: urls)
            }
        }
    }

    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text("Библиотека")
                    .font(.title.bold())
                    .foregroundStyle(EternalPalette.textPrimary)
                Spacer()
                libraryActionButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Библиотека")
                    .font(.title.bold())
                    .foregroundStyle(EternalPalette.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        libraryActionButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var libraryActionButtons: some View {
        Button {
            isFolderAlertPresented = true
        } label: {
            Label("Новая папка", systemImage: "folder.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(EternalPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .eternalCard(cornerRadius: 10)
        }

        Button {
            isImporterPresented = true
        } label: {
            Label("Импортировать", systemImage: "square.and.arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(EternalPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .eternalCard(cornerRadius: 10)
        }

        Button {
            isCreateSheetPresented = true
        } label: {
            Label("Создать сборку", systemImage: "plus")
                .font(.caption.bold())
                .foregroundStyle(EternalPalette.roseInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(EternalPalette.rose, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var searchAndSortRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                searchBox
                sortPills
            }
            VStack(alignment: .leading, spacing: 8) {
                searchBox
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        sortPills
                    }
                }
            }
        }
    }

    private var searchBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(EternalPalette.textMuted)
            TextField("Поиск по сборкам и папкам...", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(EternalPalette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .eternalCard(cornerRadius: 12)
    }

    @ViewBuilder
    private var sortPills: some View {
        ForEach(LibrarySortOption.allCases) { option in
            let active = sortOption == option
            Button {
                sortOption = option
            } label: {
                Text(option.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? EternalPalette.roseInk : EternalPalette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(active ? EternalPalette.rose : EternalPalette.cardFill)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var instancesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 14)], spacing: 14) {
            ForEach(filteredInstances) { instance in
                Button {
                    viewModel.selectedInstanceID = instance.id
                    viewModel.navigate(to: .instanceDetail(instance.id))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 120)
                            .overlay {
                                if let badge = instance.badgeText {
                                    Text(badge)
                                        .font(.title.bold())
                                        .foregroundStyle(EternalPalette.textPrimary)
                                } else {
                                    Image(systemName: "cube")
                                        .font(.system(size: 30))
                                        .foregroundStyle(EternalPalette.textSecondary)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(EternalPalette.cardStroke, lineWidth: 1)
                            )

                        Text(instance.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(EternalPalette.textPrimary)
                            .lineLimit(1)

                        Text("\(instance.engineBranch) \(instance.minecraftVersion)")
                            .font(.caption2)
                            .foregroundStyle(EternalPalette.textSecondary)
                            .lineLimit(1)

                        Divider().overlay(EternalPalette.cardStroke)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("В игре \(instance.playTimeMinutes) минут")
                            Text("Модов: \(instance.mods.count)")
                        }
                        .font(.caption2)
                        .foregroundStyle(EternalPalette.textMuted)
                    }
                    .padding(10)
                    .eternalCard(cornerRadius: 16, isSelected: instance.id == viewModel.activeInstance?.id)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        viewModel.prepareAndOpenViewport(for: instance.id)
                    } label: {
                        Label("Играть", systemImage: "play.fill")
                    }
                    if viewModel.instances.count > 1 {
                        Button(role: .destructive) {
                            viewModel.deleteInstance(instance)
                        } label: {
                            Label("Удалить сборку", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct CreateInstanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minecraftVersion = "26.3"
    @State private var engineBranch = "Horizon"
    @State private var folderTag = ""
    @State private var customFlagsText = "--metal-renderer"

    let onCreate: (String, String, String, [String], String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Новая сборка Horizon") {
                    TextField("Название сборки", text: $name)
                    TextField("Версия Horizon (напр. 26.3)", text: $minecraftVersion)
                    TextField("Профиль движка", text: $engineBranch)
                    TextField("Папка (необязательно)", text: $folderTag)
                }
                Section("Флаги запуска") {
                    TextField("--metal-renderer", text: $customFlagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Создать сборку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать") {
                        let flags = customFlagsText.split(separator: " ").map(String.init)
                        let folder = folderTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(name, minecraftVersion, engineBranch, flags, folder.isEmpty ? nil : folder)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
