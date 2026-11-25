import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Играть", systemImage: "play.circle.fill")
                }

            ContentManagerView()
                .tabItem {
                    Label("Контент", systemImage: "square.stack.3d.up.fill")
                }

            InstancesView()
                .tabItem {
                    Label("Профили", systemImage: "folder.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.orange)
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
    }
}
