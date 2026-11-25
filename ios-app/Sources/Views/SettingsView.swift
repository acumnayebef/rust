import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Игрок") {
                    TextField("Никнейм", text: $viewModel.profile.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Оффлайн режим", isOn: $viewModel.profile.offlineMode)
                }

                Section("Графика и Metal") {
                    Stepper(
                        "Дальность прорисовки: \(viewModel.graphicsSettings.renderDistance) чанков",
                        value: $viewModel.graphicsSettings.renderDistance,
                        in: 2...32
                    )

                    Picker("Лимит FPS", selection: $viewModel.graphicsSettings.maxFPS) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                        Text("120 FPS (ProMotion)").tag(120)
                    }

                    Toggle("VSync", isOn: $viewModel.graphicsSettings.vsync)
                    Toggle("MetalFX Upscaling", isOn: $viewModel.graphicsSettings.metalFXUpscaling)

                    Picker("Качество шейдеров", selection: $viewModel.graphicsSettings.shaderQuality) {
                        ForEach(ShaderQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                }

                Section("Управление") {
                    VStack(alignment: .leading) {
                        Text("Масштаб сенсорного HUD: \(viewModel.graphicsSettings.touchHUDScale, specifier: "%.2f")x")
                        Slider(value: $viewModel.graphicsSettings.touchHUDScale, in: 0.7...1.5, step: 0.05)
                    }
                    Toggle("Поддержка геймпада (MFi / DualSense)", isOn: $viewModel.graphicsSettings.enableGamepad)
                }

                Section("Хранилище (приложение Файлы)") {
                    Text(FileSystemManager.shared.launcherRootURL.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Папки mods, shaderpacks и resourcepacks доступны через стандартное приложение «Файлы» на iPhone/iPad (На этом iPhone → MC Rust Launcher).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .onChange(of: viewModel.graphicsSettings) { _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.profile) { _ in
                viewModel.saveSettings()
            }
        }
    }
}
