import SwiftUI
import UniformTypeIdentifiers

private enum SkinsSubTab: String, CaseIterable, Identifiable {
    case skins = "Скины"
    case capes = "Плащи"
    case particles = "Частицы"

    var id: String { rawValue }
}

struct SkinsView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @State private var selectedTab: SkinsSubTab = .skins
    @State private var searchText = ""
    @State private var isSkinImporterPresented = false

    private let capes = ["Без плаща", "Eternal Cape", "Horizon Cape", "Rust Edition"]

    private var filteredSkins: [SkinPreset] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return SkinPreset.defaults }
        return SkinPreset.defaults.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Скины")
                    .font(.title.bold())
                    .foregroundStyle(EternalPalette.textPrimary)

                infoBanner

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        characterPreviewPanel
                            .frame(width: 240)
                        rightContentPanel
                    }

                    VStack(spacing: 16) {
                        characterPreviewPanel
                        rightContentPanel
                    }
                }
            }
            .padding(20)
        }
        .fileImporter(
            isPresented: $isSkinImporterPresented,
            allowedContentTypes: [.png, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                viewModel.importCustomSkin(urls: urls)
            }
        }
    }

    private var infoBanner: some View {
        Text("«\(viewModel.profile.username)» — профиль Rust-клиента. Выбранный скин, плащ и частицы применяются к профилю и передаются клиенту при запуске.")
            .font(.caption)
            .foregroundStyle(EternalPalette.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eternalCard(cornerRadius: 12)
    }

    private var characterPreviewPanel: some View {
        VStack(spacing: 14) {
            PixelCharacterView(
                skin: viewModel.activeSkin,
                particle: viewModel.profile.selectedParticle,
                scale: 1.05
            )
            .frame(height: 270)

            Text(viewModel.profile.username)
                .font(.subheadline.bold())
                .foregroundStyle(EternalPalette.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .eternalCard(cornerRadius: 16)
    }

    private var rightContentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SkinsSubTab.allCases) { tab in
                        let active = selectedTab == tab
                        Button {
                            selectedTab = tab
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

                    Button {
                        isSkinImporterPresented = true
                    } label: {
                        Label("Добавить скин", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EternalPalette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .eternalCard(cornerRadius: 10)
                    }

                    if selectedTab == .skins {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(EternalPalette.textMuted)
                            TextField("Поиск среди \(SkinPreset.defaults.count) скинов", text: $searchText)
                                .font(.caption)
                                .foregroundStyle(EternalPalette.textPrimary)
                                .frame(minWidth: 130)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .eternalCard(cornerRadius: 10)
                    }
                }
            }

            switch selectedTab {
            case .skins:
                skinsGrid
            case .capes:
                capesGrid
            case .particles:
                particlesGrid
            }
        }
    }

    private var skinsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            ForEach(filteredSkins) { skin in
                let selected = viewModel.profile.selectedSkinID == skin.id
                Button {
                    viewModel.profile.selectedSkinID = skin.id
                    viewModel.saveSettings()
                } label: {
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "trash")
                                .font(.caption2)
                                .foregroundStyle(selected ? EternalPalette.rose : EternalPalette.textMuted)
                        }

                        PixelCharacterView(skin: skin, particle: .none, scale: 0.48)
                            .frame(height: 118)

                        Text(skin.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(EternalPalette.textPrimary)

                        Text(skin.modelKind.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(EternalPalette.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .padding(12)
                    .eternalCard(cornerRadius: 14, isSelected: selected)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var capesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
            ForEach(capes, id: \.self) { cape in
                let selected = viewModel.profile.selectedCapeName == cape
                Button {
                    viewModel.profile.selectedCapeName = cape
                    viewModel.saveSettings()
                } label: {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                cape == "Без плаща"
                                    ? Color.white.opacity(0.04)
                                    : EternalPalette.rose.opacity(0.35)
                            )
                            .frame(width: 58, height: 86)
                            .overlay {
                                if cape == "Без плаща" {
                                    Text("НЕТ")
                                        .font(.caption2)
                                        .foregroundStyle(EternalPalette.textMuted)
                                } else {
                                    Image(systemName: "flag.fill")
                                        .font(.title3)
                                        .foregroundStyle(EternalPalette.rose)
                                }
                            }
                        Text(cape)
                            .font(.subheadline.bold())
                            .foregroundStyle(EternalPalette.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .eternalCard(cornerRadius: 14, isSelected: selected)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var particlesGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                ForEach(ParticleOption.allCases) { option in
                    let selected = viewModel.profile.selectedParticle == option
                    Button {
                        viewModel.profile.selectedParticle = option
                        viewModel.saveSettings()
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if selected {
                                    Text("Надето")
                                        .font(.caption2.bold())
                                        .foregroundStyle(EternalPalette.roseInk)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(EternalPalette.rose, in: Capsule())
                                } else if option == .hearts {
                                    Text("Premium")
                                        .font(.caption2.bold())
                                        .foregroundStyle(EternalPalette.roseInk)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(EternalPalette.gold, in: Capsule())
                                }
                                Spacer()
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.28))
                                    .frame(height: 110)

                                if option == .none {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                        .foregroundStyle(EternalPalette.textMuted)
                                        .frame(width: 66, height: 84)
                                        .overlay {
                                            Text("НЕТ")
                                                .font(.caption2)
                                                .foregroundStyle(EternalPalette.textMuted)
                                        }
                                } else {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 38))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.pink, Color(red: 0.90, green: 0.25, blue: 0.45)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                            }

                            Text(option.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(EternalPalette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(12)
                        .eternalCard(cornerRadius: 14, isSelected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Сердечки отображаются вокруг персонажа в главном меню и при запуске Rust-клиента Horizon.")
                .font(.caption)
                .foregroundStyle(EternalPalette.textMuted)
        }
    }
}
