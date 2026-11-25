import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @State private var isConsoleExpanded = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    instanceCard
                    contentSummaryRow
                    launchButton
                    consoleSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MC Rust Launcher")
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: "cube.transparent.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Minecraft Rust Edition")
                    .font(.headline)
                HStack(spacing: 8) {
                    Label("Core v\(viewModel.coreVersionText)", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(viewModel.isNativeCoreLinked ? "XCFramework активен" : "Preview режим")
                        .font(.caption)
                        .foregroundStyle(viewModel.isNativeCoreLinked ? .green : .yellow)
                }
            }

            Spacer()

            Text(viewModel.engineState.displayTitle)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var instanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Активный профиль")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.instances.count > 1 {
                    Menu("Сменить") {
                        ForEach(viewModel.instances) { instance in
                            Button(instance.name) {
                                viewModel.selectedInstanceID = instance.id
                                viewModel.refreshActiveInstanceContent()
                            }
                        }
                    }
                    .font(.subheadline)
                }
            }

            if let instance = viewModel.activeInstance {
                Text(instance.name)
                    .font(.title3.bold())
                HStack(spacing: 12) {
                    Label("MC \(instance.minecraftVersion)", systemImage: "tag")
                    Label(instance.engineBranch, systemImage: "arrow.triangle.branch")
                    Label(viewModel.profile.username, systemImage: "person.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var contentSummaryRow: some View {
        let instance = viewModel.activeInstance
        let activeMods = instance?.mods.filter(\.enabled).count ?? 0
        let activeShaders = instance?.shaders.filter(\.enabled).count ?? 0
        let activePacks = instance?.resourcePacks.filter(\.enabled).count ?? 0

        return HStack(spacing: 10) {
            summaryBadge(title: "Моды", count: activeMods, icon: "puzzlepiece.extension", color: .blue)
            summaryBadge(title: "Шейдеры", count: activeShaders, icon: "sparkles", color: .purple)
            summaryBadge(title: "Ресурспаки", count: activePacks, icon: "photo.stack", color: .teal)
        }
    }

    private func summaryBadge(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var launchButton: some View {
        Button {
            viewModel.prepareAndOpenViewport()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("Запустить Rust Client")
                    .fontWeight(.bold)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.orange, .deepOrange],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    private var consoleSection: some View {
        DisclosureGroup(isExpanded: $isConsoleExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.logs.isEmpty {
                    Text("Логи ядра появятся здесь после запуска.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.logs.suffix(60)) { entry in
                                Text("[\(entry.level.label)] \(entry.message)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(color(for: entry.level))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 180)
                }

                HStack {
                    Spacer()
                    Button("Очистить консоль", role: .destructive) {
                        viewModel.clearLogs()
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Консоль Rust Core (\(viewModel.logs.count))", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warn: return .yellow
        case .error: return .red
        }
    }
}

private extension Color {
    static let deepOrange = Color(red: 0.90, green: 0.30, blue: 0.10)
}
