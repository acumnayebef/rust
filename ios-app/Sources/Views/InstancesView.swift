import SwiftUI

struct InstancesView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @State private var isCreateSheetPresented = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.instances) { instance in
                    Button {
                        viewModel.selectedInstanceID = instance.id
                        viewModel.refreshActiveInstanceContent()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(instance.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if instance.id == viewModel.activeInstance?.id {
                                        Text("Активный")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundStyle(.orange)
                                            .clipShape(Capsule())
                                    }
                                }

                                Text("MC \(instance.minecraftVersion) • \(instance.engineBranch)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Моды: \(instance.mods.count) | Шейдеры: \(instance.shaders.count) | Паки: \(instance.resourcePacks.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if instance.id == viewModel.activeInstance?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if viewModel.instances.count > 1 {
                            Button(role: .destructive) {
                                viewModel.deleteInstance(instance)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Профили клиента")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreateSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreateSheetPresented) {
                CreateInstanceSheet { name, mcVersion, branch, flags in
                    viewModel.createInstance(
                        name: name,
                        minecraftVersion: mcVersion,
                        engineBranch: branch,
                        flags: flags
                    )
                }
            }
        }
    }
}

private struct CreateInstanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minecraftVersion = "1.21.4"
    @State private var engineBranch = "custom-rust-main"
    @State private var customFlagsText = "--metal-renderer"

    let onCreate: (String, String, String, [String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название профиля", text: $name)
                    TextField("Версия Minecraft (напр. 1.21.4)", text: $minecraftVersion)
                    TextField("Ветка/профиль движка", text: $engineBranch)
                }

                Section("Флаги запуска движка") {
                    TextField("--metal-renderer --async-chunks", text: $customFlagsText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Новый профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать") {
                        let flags = customFlagsText
                            .split(separator: " ")
                            .map(String.init)
                        onCreate(name, minecraftVersion, engineBranch, flags)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
