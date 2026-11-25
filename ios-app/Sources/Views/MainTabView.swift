import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel

    var body: some View {
        ZStack {
            EternalWindowBackground()

            VStack(spacing: 0) {
                topTitleBar

                HStack(spacing: 0) {
                    if viewModel.currentRoute != .home {
                        leftNavigationRail
                    }

                    routeDestinationView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.isShowingViewport) {
            GameViewportView()
                .environmentObject(viewModel)
        }
        .alert(
            "Ошибка",
            isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { if !$0 { viewModel.lastErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.lastErrorMessage ?? "")
        }
        .alert("Файлы игры не импортированы", isPresented: $viewModel.showMissingGameFilesAlert) {
            Button("Перейти в Настройки") {
                viewModel.navigate(to: .settings)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Перед запуском клиента импортируйте файлы игры в Настройках («Импортировать файлы игры»).")
        }
    }

    private var topTitleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .foregroundStyle(viewModel.canGoBack ? EternalPalette.textPrimary : EternalPalette.textMuted)
                }
                .disabled(!viewModel.canGoBack)

                Text(routeDisplayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(EternalPalette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "cube.fill")
                    .font(.caption)
                    .foregroundStyle(EternalPalette.rose)
                Text("Eternal Launcher")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EternalPalette.textPrimary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.engineState == .running ? Color.green : EternalPalette.textMuted)
                    .frame(width: 6, height: 6)
                Text(viewModel.engineState.displayTitle)
                    .font(.caption2)
                    .foregroundStyle(EternalPalette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(EternalPalette.panelFill, in: Capsule())
            .overlay(Capsule().stroke(EternalPalette.cardStroke, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.32))
    }

    private var leftNavigationRail: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.navigate(to: .home)
            } label: {
                PixelHeadView(skin: viewModel.activeSkin, size: 30)
            }
            .padding(.top, 8)

            railIcon(systemName: "house", route: .home)
            railIcon(systemName: "magnifyingglass", route: .catalog)
            railIcon(systemName: "books.vertical", route: .library)
            railIcon(systemName: "tshirt", route: .skins)
            railIcon(systemName: "camera", route: .screenshots)
            railIcon(systemName: "chart.bar", route: .stats)

            Spacer()

            Button {
                viewModel.navigate(to: .skins)
            } label: {
                Image(systemName: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(EternalPalette.gold)
                    .frame(width: 34, height: 34)
                    .background(EternalPalette.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }

            railIcon(systemName: "gearshape", route: .settings)
                .padding(.bottom, 10)
        }
        .frame(width: 50)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(EternalPalette.cardStroke)
                .frame(width: 1)
        }
    }

    private func railIcon(systemName: String, route: AppRoute) -> some View {
        let isActive: Bool = {
            if case .instanceDetail = viewModel.currentRoute, route == .library {
                return true
            }
            return viewModel.currentRoute == route
        }()

        return Button {
            viewModel.navigate(to: route)
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isActive ? EternalPalette.roseInk : EternalPalette.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? EternalPalette.rose : Color.clear)
                )
        }
    }

    @ViewBuilder
    private var routeDestinationView: some View {
        switch viewModel.currentRoute {
        case .home:
            HomeView()
        case .catalog:
            ContentManagerView(instanceID: viewModel.activeInstance?.id, initialTab: .mods)
        case .library:
            InstancesView()
        case .skins:
            SkinsView()
        case .screenshots:
            ScreenshotsPlaceholderView()
        case .stats:
            StatsView()
        case .settings:
            SettingsView()
        case .instanceDetail(let id):
            ContentManagerView(instanceID: id, initialTab: .mods)
        }
    }

    private var routeDisplayTitle: String {
        switch viewModel.currentRoute {
        case .instanceDetail(let id):
            return viewModel.instance(for: id)?.name ?? "Сборка"
        default:
            return viewModel.currentRoute.title
        }
    }
}

private struct ScreenshotsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 46))
                .foregroundStyle(EternalPalette.rose)
            Text("Скриншоты")
                .font(.title2.bold())
                .foregroundStyle(EternalPalette.textPrimary)
            Text("Снимки экрана импортированного клиента сохраняются в Documents/MCRustLauncher/screenshots.")
                .font(.subheadline)
                .foregroundStyle(EternalPalette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
    }
}

private struct StatsView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Статистика")
                    .font(.title.bold())
                    .foregroundStyle(EternalPalette.textPrimary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    statCard("Всего в игре", value: "\(viewModel.totalPlayTimeMinutes) мин", icon: "clock.fill")
                    statCard("Сборок Horizon", value: "\(viewModel.instances.count)", icon: "books.vertical.fill")
                    statCard("Модов в каталоге", value: "\(viewModel.horizonProjects.count)", icon: "puzzlepiece.extension.fill")
                    statCard(
                        "Файлы игры",
                        value: viewModel.importedGameFiles.isImported ? "\(viewModel.importedGameFiles.fileCount) файлов" : "Не импортированы",
                        icon: "folder.fill"
                    )
                }
            }
            .padding()
        }
    }

    private func statCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(EternalPalette.rose)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(EternalPalette.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(EternalPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .eternalCard()
    }
}
