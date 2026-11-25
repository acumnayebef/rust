import SwiftUI
import UniformTypeIdentifiers

struct ContentManagerView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @State private var selectedKind: ContentKind = .mod
    @State private var isImporterPresented = false
    @State private var isModrinthPresented = false

    private var allowedContentTypes: [UTType] {
        var types: [UTType] = [.zip, .archive, .folder, .data, .item]
        if let jarType = UTType(filenameExtension: "jar") {
            types.append(jarType)
        }
        if let wasmType = UTType(filenameExtension: "wasm") {
            types.append(wasmType)
        }
        return types
    }

    private var currentItems: [ContentItem] {
        viewModel.activeInstance?.items(for: selectedKind) ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Категория", selection: $selectedKind) {
                    ForEach(ContentKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if currentItems.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(currentItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: selectedKind.systemImage)
                                    .foregroundStyle(item.enabled ? .orange : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body.weight(.medium))
                                    Text("\(item.fileName) • \(formatSize(item.sizeBytes))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { item.enabled },
                                        set: { _ in viewModel.toggleContentItem(item) }
                                    )
                                )
                                .labelsHidden()
                            }
                        }
                        .onDelete { offsets in
                            viewModel.deleteContentItems(kind: selectedKind, at: offsets)
                        }
                        .onMove { source, destination in
                            viewModel.moveContentItems(kind: selectedKind, from: source, to: destination)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Контент")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedKind == .resourcePack && !currentItems.isEmpty {
                        EditButton()
                    }
                    Button {
                        viewModel.refreshActiveInstanceContent()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Menu {
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Импортировать из Файлов", systemImage: "folder.badge.plus")
                        }
                        Button {
                            isModrinthPresented = true
                        } label: {
                            Label("Скачать с Modrinth", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.importLocalFiles(urls: urls, kind: selectedKind)
                case .failure(let error):
                    viewModel.lastErrorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $isModrinthPresented) {
                ModrinthBrowserView(initialKind: selectedKind)
                    .environmentObject(viewModel)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: selectedKind.systemImage)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("Список «\(selectedKind.title)» пуст")
                .font(.headline)
            Text("Импортируйте файлы (.wasm, .dylib, .zip, .jar или папку) либо скачайте напрямую из каталога Modrinth.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Из Файлов") {
                    isImporterPresented = true
                }
                .buttonStyle(.bordered)

                Button("Modrinth") {
                    isModrinthPresented = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            Spacer()
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "папка" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
