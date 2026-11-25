# MC Rust Launcher (iOS)

Собственный iOS-лаунчер на **SwiftUI + Metal** с универсальным **C-FFI / XCFramework** мостом для запуска кастомного клиента **Minecraft Rust Edition** с поддержкой **модов**, **шейдеров** и **ресурспаков**.

## Структура проекта

```text
MCRustLauncher/
├── rust-core/
│   ├── Cargo.toml
│   ├── include/
│   │   ├── mc_rust_core.h          # C-FFI заголовок для Swift
│   │   └── module.modulemap        # Clang module MCRustCore
│   ├── scripts/
│   │   └── build-xcframework.sh    # Сборка libmc_rust_core.a -> MCRustCore.xcframework
│   └── src/
│       ├── lib.rs                  # Трейт EngineRuntime и экспорты mc_rust_*
│       ├── config.rs               # LaunchConfig + валидация путей
│       └── content.rs              # Инспектор модов, шейдеров и pack.mcmeta
├── ios-app/
│   ├── project.yml                 # Конфигурация XcodeGen
│   ├── Resources/Info.plist        # Доступ к папке приложения через «Файлы» (iOS)
│   └── Sources/
│       ├── MCRustLauncherApp.swift
│       ├── Models/LauncherModels.swift
│       ├── Services/
│       │   ├── FileSystemManager.swift
│       │   ├── ModrinthClient.swift
│       │   ├── RustBridge.swift
│       │   └── LauncherViewModel.swift
│       └── Views/
│           ├── MainTabView.swift
│           ├── HomeView.swift
│           ├── ContentManagerView.swift
│           ├── ModrinthBrowserView.swift
│           ├── InstancesView.swift
│           ├── SettingsView.swift
│           └── GameViewportView.swift
└── .github/workflows/
    └── build-ios.yml               # Облачная сборка .ipa на macOS-15
```

## Подключение своего Rust-клиента

Весь ваш движок подключается через трейт `EngineRuntime` в [rust-core/src/lib.rs](rust-core/src/lib.rs):

1. Добавьте крейт вашего клиента (например, с `wgpu` и рендерером под Metal) в `rust-core/Cargo.toml`.
2. Реализуйте `EngineRuntime` (или замените `CustomRustClientRuntime`), используя переданный из Swift `metal_layer_ptr` (`CAMetalLayer *`), список включённых модов, шейдеров и ресурспаков из `ContentManifestSummary`, а также параметры `GraphicsConfig`.
3. Внутри `mc_rust_engine_start` лаунчер автоматически валидирует JSON-конфигурацию, проверяет наличие файлов на диске и перенаправляет все логи движка обратно в консоль SwiftUI.

## Моды, шейдеры и ресурспаки

Для каждого профиля в `Documents/MCRustLauncher/instances/<id>/` создаются отдельные директории:
- `mods/` — `.wasm`, `.dylib`, `.zip`, `.jar` или директории модов
- `shaderpacks/` — архивы `.zip` или распакованные папки шейдеров
- `resourcepacks/` — `.zip` / `.mcpack` / папки (поддерживается чтение `pack.mcmeta` и изменение порядка приоритета в UI)

Добавлять контент можно тремя способами:
1. Через вкладку **Контент → + → Из Файлов** (импорт из iOS «Файлы» / iCloud Drive).
2. Через вкладку **Контент → + → Скачать с Modrinth** (встроенный поиск и загрузка).
3. Напрямую через стандартное приложение **Файлы** на iPhone/iPad (`На этом iPhone → MC Rust Launcher`).

## Как собрать `.ipa` с Windows

Поскольку для компиляции под iOS требуется macOS и Xcode:

1. Создайте репозиторий на GitHub и запушьте содержимое `D:\MCRustLauncher`.
2. Вкладка **Actions → Build iOS Launcher (.ipa)** автоматически соберёт `MCRustCore.xcframework`, сгенерирует Xcode-проект через `xcodegen` и выдаст артефакт `MCRustLauncher-unsigned.ipa`.
3. Установите полученный `.ipa` на iPhone/iPad через **AltStore**, **SideStore** или **TrollStore**.

Если у вас есть Mac локально:
```bash
./rust-core/scripts/build-xcframework.sh
cd ios-app && xcodegen generate && open MCRustLauncher.xcodeproj
```
