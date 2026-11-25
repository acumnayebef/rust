import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width >= 680

            ZStack {
                StarryHorizonBackdrop()

                VStack(spacing: 12) {
                    topGreetingRow

                    if isWide {
                        HStack(alignment: .center, spacing: 16) {
                            leftMenuCards
                                .frame(width: 210)
                            Spacer()
                            PixelCharacterView(
                                skin: viewModel.activeSkin,
                                particle: viewModel.profile.selectedParticle,
                                scale: 1.05
                            )
                            Spacer()
                            continueCard
                                .frame(width: 220)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                PixelCharacterView(
                                    skin: viewModel.activeSkin,
                                    particle: viewModel.profile.selectedParticle,
                                    scale: 0.9
                                )
                                .frame(height: 230)

                                LazyVGrid(
                                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                                    spacing: 10
                                ) {
                                    menuCard(title: "Библиотека", subtitle: "\(viewModel.instances.count) сборок", icon: "books.vertical.fill", tint: .orange) {
                                        viewModel.navigate(to: .library)
                                    }
                                    menuCard(title: "Скины", subtitle: viewModel.activeSkin.name, icon: "tshirt.fill", tint: .blue) {
                                        viewModel.navigate(to: .skins)
                                    }
                                    menuCard(title: "Плащи", subtitle: viewModel.profile.selectedCapeName, icon: "flag.fill", tint: .pink) {
                                        viewModel.navigate(to: .skins)
                                    }
                                    menuCard(title: "Моды и сборки", subtitle: "Поиск Horizon", icon: "magnifyingglass", tint: .cyan) {
                                        viewModel.navigate(to: .catalog)
                                    }
                                    menuCard(title: "Скриншоты", subtitle: nil, icon: "photo.on.rectangle.angled", tint: .teal) {
                                        viewModel.navigate(to: .screenshots)
                                    }
                                    menuCard(title: "Статистика", subtitle: nil, icon: "chart.bar.fill", tint: .green) {
                                        viewModel.navigate(to: .stats)
                                    }
                                }

                                continueCard
                            }
                        }
                    }

                    bottomPlayBar
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private var topGreetingRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.caption)
                    .foregroundStyle(EternalPalette.textSecondary)
                Text(viewModel.profile.username)
                    .font(.title2.bold())
                    .foregroundStyle(EternalPalette.textPrimary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    viewModel.navigate(to: .skins)
                } label: {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(EternalPalette.gold)
                        .frame(width: 36, height: 36)
                        .eternalCard(cornerRadius: 10)
                }

                Button {
                    viewModel.navigate(to: .settings)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline)
                        .foregroundStyle(EternalPalette.textSecondary)
                        .frame(width: 36, height: 36)
                        .eternalCard(cornerRadius: 10)
                }
            }
        }
    }

    private var leftMenuCards: some View {
        VStack(spacing: 8) {
            menuCard(title: "Библиотека", subtitle: "\(viewModel.instances.count) сборок", icon: "books.vertical.fill", tint: .orange) {
                viewModel.navigate(to: .library)
            }
            menuCard(title: "Скины", subtitle: nil, icon: "tshirt.fill", tint: .blue) {
                viewModel.navigate(to: .skins)
            }
            menuCard(title: "Плащи", subtitle: nil, icon: "flag.fill", tint: .pink) {
                viewModel.navigate(to: .skins)
            }
            menuCard(title: "Моды и сборки", subtitle: "Поиск", icon: "magnifyingglass", tint: .cyan) {
                viewModel.navigate(to: .catalog)
            }
            menuCard(title: "Скриншоты", subtitle: nil, icon: "photo.on.rectangle.angled", tint: .teal) {
                viewModel.navigate(to: .screenshots)
            }
            menuCard(title: "Статистика", subtitle: nil, icon: "chart.bar.fill", tint: .green) {
                viewModel.navigate(to: .stats)
            }
        }
    }

    private func menuCard(title: String, subtitle: String?, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(EternalPalette.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(EternalPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .eternalCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private var continueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПРОДОЛЖИТЬ")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(EternalPalette.textSecondary)

            ForEach(viewModel.worldShortcuts) { shortcut in
                Button {
                    viewModel.prepareAndOpenViewport()
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(shortcut.isServer ? Color.white.opacity(0.08) : Color.green.opacity(0.24))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: shortcut.isServer ? "server.rack" : "globe.europe.africa.fill")
                                    .font(.caption)
                                    .foregroundStyle(shortcut.isServer ? EternalPalette.textSecondary : .green)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(EternalPalette.textPrimary)
                                .lineLimit(1)
                            Text(shortcut.subtitle)
                                .font(.caption2)
                                .foregroundStyle(EternalPalette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .eternalCard(cornerRadius: 14)
    }

    private var bottomPlayBar: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "cube")
                        .font(.title3)
                        .foregroundStyle(EternalPalette.textSecondary)
                }

            if let instance = viewModel.activeInstance {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ПОСЛЕДНЯЯ ИГРА")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(EternalPalette.textMuted)

                    Menu {
                        ForEach(viewModel.instances) { item in
                            Button(item.name) {
                                viewModel.selectedInstanceID = item.id
                                viewModel.refreshActiveInstanceContent()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(instance.name)
                                .font(.headline.bold())
                                .foregroundStyle(EternalPalette.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(EternalPalette.textSecondary)
                        }
                    }

                    Text("\(instance.engineBranch) \(instance.minecraftVersion) • Всего в игре \(instance.playTimeMinutes) мин")
                        .font(.caption2)
                        .foregroundStyle(EternalPalette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Открыть") {
                    viewModel.navigate(to: .instanceDetail(instance.id))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(EternalPalette.textSecondary)
                .padding(.horizontal, 8)
            } else {
                Spacer()
            }

            Button {
                viewModel.prepareAndOpenViewport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                    Text("Играть")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(EternalPalette.roseInk)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(EternalPalette.rose, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .eternalCard(cornerRadius: 16)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Доброго утра,"
        case 12..<18: return "Добрый день,"
        case 18..<23: return "Добрый вечер,"
        default: return "Доброй ночи,"
        }
    }
}
