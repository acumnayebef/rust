import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @State private var isGameFilesImporterPresented = false

    private var gameFileTypes: [UTType] {
        var types: [UTType] = [.folder, .zip, .archive, .data, .item]
        for ext in ["dylib", "wasm", "ipa", "hmod"] {
            if let ut = UTType(filenameExtension: ext) {
                types.append(ut)
            }
        }
        return types
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Настройки")
                    .font(.title.bold())
                    .foregroundStyle(EternalPalette.textPrimary)

                gameFilesSection
                playerSection
                graphicsSection
                controlsSection
                storageSection
            }
            .padding(20)
        }
        .fileImporter(
            isPresented: $isGameFilesImporterPresented,
            allowedContentTypes: gameFileTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importGameFiles(urls: urls)
            case .failure(let error):
                viewModel.lastErrorMessage = error.localizedDescription
            }
        }
        .onChange(of: viewModel.graphicsSettings) { _ in
            viewModel.saveSettings()
        }
        .onChange(of: viewModel.profile) { _ in
            viewModel.saveSettings()
        }
    }

    private var gameFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(EternalPalette.rose)
                Text("Файлы игры (Minecraft Rust Edition)")
                    .font(.headline)
                    .foregroundStyle(EternalPalette.textPrimary)
                Spacer()
            }

            if viewModel.importedGameFiles.isImported {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Импортировано: \(viewModel.importedGameFiles.fileCount) файлов (\(viewModel.importedGameFiles.formattedSize))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    if let entry = viewModel.importedGameFiles.detectedEntrypoint {
                        Text("Модуль/архив запуска: \(entry)")
                            .font(.caption)
                            .foregroundStyle(EternalPalette.textSecondary)
                    }
                }
            } else {
                Text("Файлы игры ещё не импортированы. При нажатии «Играть» лаунчер запустит именно импортированный вами клиент.")
                    .font(.caption)
                    .foregroundStyle(EternalPalette.textSecondary)
            }

            HStack(spacing: 10) {
                Button {
                    isGameFilesImporterPresented = true
                } label: {
                    Label("Импортировать файлы игры", systemImage: "square.and.arrow.down.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(EternalPalette.roseInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(EternalPalette.rose, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if viewModel.importedGameFiles.isImported {
                    Button(role: .destructive) {
                        viewModel.clearGameFiles()
                    } label: {
                        Text("Очистить")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .eternalCard(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .eternalCard(cornerRadius: 16, isSelected: !viewModel.importedGameFiles.isImported)
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Игрок")
                .font(.headline)
                .foregroundStyle(EternalPalette.textPrimary)

            TextField("Никнейм", text: $viewModel.profile.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(EternalPalette.textPrimary)

            Toggle("Оффлайн режим", isOn: $viewModel.profile.offlineMode)
                .tint(EternalPalette.rose)
                .foregroundStyle(EternalPalette.textPrimary)
        }
        .padding(16)
        .eternalCard(cornerRadius: 16)
    }

    private var graphicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Графика и Metal")
                .font(.headline)
                .foregroundStyle(EternalPalette.textPrimary)

            Stepper(
                "Дальность прорисовки: \(viewModel.graphicsSettings.renderDistance) чанков",
                value: $viewModel.graphicsSettings.renderDistance,
                in: 2...32
            )
            .foregroundStyle(EternalPalette.textPrimary)

            HStack {
                Text("Лимит FPS")
                    .foregroundStyle(EternalPalette.textPrimary)
                Spacer()
                Picker("Лимит FPS", selection: $viewModel.graphicsSettings.maxFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                    Text("120 FPS").tag(120)
                }
                .tint(EternalPalette.rose)
            }

            Toggle("VSync", isOn: $viewModel.graphicsSettings.vsync)
                .tint(EternalPalette.rose)
                .foregroundStyle(EternalPalette.textPrimary)

            Toggle("MetalFX Upscaling", isOn: $viewModel.graphicsSettings.metalFXUpscaling)
                .tint(EternalPalette.rose)
                .foregroundStyle(EternalPalette.textPrimary)

            HStack {
                Text("Качество шейдеров")
                    .foregroundStyle(EternalPalette.textPrimary)
                Spacer()
                Picker("Качество шейдеров", selection: $viewModel.graphicsSettings.shaderQuality) {
                    ForEach(ShaderQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .tint(EternalPalette.rose)
            }
        }
        .padding(16)
        .eternalCard(cornerRadius: 16)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Управление")
                .font(.headline)
                .foregroundStyle(EternalPalette.textPrimary)

            Text("Масштаб сенсорного HUD: \(viewModel.graphicsSettings.touchHUDScale, specifier: "%.2f")x")
                .font(.subheadline)
                .foregroundStyle(EternalPalette.textPrimary)

            Slider(value: $viewModel.graphicsSettings.touchHUDScale, in: 0.7...1.5, step: 0.05)
                .tint(EternalPalette.rose)

            Toggle("Поддержка геймпада (MFi / DualSense)", isOn: $viewModel.graphicsSettings.enableGamepad)
                .tint(EternalPalette.rose)
                .foregroundStyle(EternalPalette.textPrimary)
        }
        .padding(16)
        .eternalCard(cornerRadius: 16)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Хранилище (Файлы iOS)")
                .font(.headline)
                .foregroundStyle(EternalPalette.textPrimary)

            Text(FileSystemManager.shared.gameFilesDirectoryURL.path)
                .font(.caption2)
                .foregroundStyle(EternalPalette.textMuted)
                .textSelection(.enabled)

            Text("Папки game-files, mods, shaderpacks и resourcepacks также доступны через приложение «Файлы» на iPhone/iPad.")
                .font(.caption)
                .foregroundStyle(EternalPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .eternalCard(cornerRadius: 16)
    }
}
