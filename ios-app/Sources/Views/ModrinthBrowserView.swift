import SwiftUI

struct ModrinthBrowserView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKind: ContentKind
    @State private var query: String = ""
    @State private var projects: [ModrinthProject] = []
    @State private var isLoading = false
    @State private var downloadingProjectID: String?
    @State private var statusBanner: String?

    init(initialKind: ContentKind) {
        _selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Тип контента", selection: $selectedKind) {
                    ForEach(ContentKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if let banner = statusBanner {
                    Text(banner)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                if isLoading && projects.isEmpty {
                    Spacer()
                    ProgressView("Поиск на Modrinth...")
                    Spacer()
                } else {
                    List(projects) { project in
                        HStack(alignment: .top, spacing: 12) {
                            AsyncImage(url: project.iconUrl.flatMap(URL.init(string:))) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.2))
                                    .overlay {
                                        Image(systemName: selectedKind.systemImage)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(.headline)
                                Text(project.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text("\(project.author) • \(project.downloads.formatted()) скачиваний")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if downloadingProjectID == project.projectId {
                                ProgressView()
                            } else {
                                Button("Скачать") {
                                    Task {
                                        await download(project)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Каталог Modrinth")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Поиск модов, шейдеров, ресурспаков")
            .onSubmit(of: .search) {
                Task { await performSearch() }
            }
            .onChange(of: selectedKind) { _ in
                Task { await performSearch() }
            }
            .task {
                await performSearch()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await performSearch() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
    }

    private func performSearch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await ModrinthClient.shared.search(query: query, kind: selectedKind)
        } catch {
            viewModel.lastErrorMessage = error.localizedDescription
        }
    }

    private func download(_ project: ModrinthProject) async {
        downloadingProjectID = project.projectId
        defer { downloadingProjectID = nil }
        do {
            try await viewModel.installFromModrinth(project: project, kind: selectedKind)
            statusBanner = "Установлено: \(project.title)"
        } catch {
            viewModel.lastErrorMessage = error.localizedDescription
        }
    }
}
