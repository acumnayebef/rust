import Foundation
import QuartzCore

#if canImport(MCRustCore)
import MCRustCore
#endif

private final class LogSink: @unchecked Sendable {
    let handler: @Sendable (LogLevel, String) -> Void

    init(handler: @escaping @Sendable (LogLevel, String) -> Void) {
        self.handler = handler
    }
}

#if canImport(MCRustCore)
private func rustLogTrampoline(
    level: Int32,
    messagePtr: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    let sink = Unmanaged<LogSink>.fromOpaque(userData).takeUnretainedValue()
    let message = messagePtr.map { String(cString: $0) } ?? ""
    let logLevel = LogLevel(rawValue: Int(level)) ?? .info
    sink.handler(logLevel, message)
}
#endif

@MainActor
final class RustBridge {
    static let shared = RustBridge()

    private var activeLogSink: Unmanaged<LogSink>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    var isNativeCoreLinked: Bool {
        #if canImport(MCRustCore)
        return true
        #else
        return false
        #endif
    }

    var coreVersion: String {
        #if canImport(MCRustCore)
        guard let ptr = mc_rust_core_version() else { return "unknown" }
        return String(cString: ptr)
        #else
        return "0.1.0-preview"
        #endif
    }

    func currentStatus() -> EngineState {
        #if canImport(MCRustCore)
        return EngineState(rawValue: Int(mc_rust_engine_status())) ?? .idle
        #else
        return .idle
        #endif
    }

    func validateConfig(_ payload: RustLaunchConfigPayload) -> RustValidationReport {
        guard let jsonData = try? encoder.encode(payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return RustValidationReport(
                valid: false,
                errors: ["Не удалось сериализовать LaunchConfig в JSON."],
                warnings: [],
                activeMods: nil,
                activeShaders: nil,
                activeResourcePacks: nil
            )
        }

        #if canImport(MCRustCore)
        let rawPtr: UnsafeMutablePointer<CChar>? = jsonString.withCString { cString in
            mc_rust_engine_validate_config(cString)
        }
        guard let rawPtr else {
            return RustValidationReport(
                valid: false,
                errors: ["mc_rust_engine_validate_config вернул NULL."],
                warnings: [],
                activeMods: nil,
                activeShaders: nil,
                activeResourcePacks: nil
            )
        }
        defer { mc_rust_string_free(rawPtr) }

        let responseString = String(cString: rawPtr)
        if let responseData = responseString.data(using: .utf8),
           let report = try? decoder.decode(RustValidationReport.self, from: responseData) {
            return report
        }
        return RustValidationReport(
            valid: false,
            errors: ["Некорректный JSON-ответ валидации от Rust Core."],
            warnings: [],
            activeMods: nil,
            activeShaders: nil,
            activeResourcePacks: nil
        )
        #else
        return RustValidationReport(
            valid: true,
            errors: [],
            warnings: ["Сборка без MCRustCore.xcframework (режим SwiftUI Preview)."],
            activeMods: payload.mods.filter(\.enabled).count,
            activeShaders: payload.shaders.filter(\.enabled).count,
            activeResourcePacks: payload.resourcePacks.filter(\.enabled).count
        )
        #endif
    }

    func start(
        payload: RustLaunchConfigPayload,
        metalLayer: CAMetalLayer?,
        onLog: @escaping @Sendable (LogLevel, String) -> Void
    ) -> Int32 {
        guard let jsonData = try? encoder.encode(payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            onLog(.error, "Не удалось закодировать конфигурацию запуска в JSON.")
            return -1
        }

        #if canImport(MCRustCore)
        if activeLogSink != nil {
            _ = stop()
        }

        let sink = LogSink(handler: onLog)
        let retainedSink = Unmanaged.passRetained(sink)
        activeLogSink = retainedSink

        let layerPtr = metalLayer.map { Unmanaged.passUnretained($0).toOpaque() }
        let status = jsonString.withCString { cString in
            mc_rust_engine_start(
                cString,
                layerPtr,
                rustLogTrampoline,
                retainedSink.toOpaque()
            )
        }

        if status != 0 {
            activeLogSink?.release()
            activeLogSink = nil
        }
        return status
        #else
        onLog(.warn, "MCRustCore.xcframework не подключён — запущен демонстрационный режим превью.")
        onLog(.info, "Инстанс '\(payload.instanceName)' (MC \(payload.minecraftVersion)) готов.")
        onLog(.info, "Моды: \(payload.mods.filter(\.enabled).count), шейдеры: \(payload.shaders.filter(\.enabled).count), ресурспаки: \(payload.resourcePacks.filter(\.enabled).count).")
        return 0
        #endif
    }

    @discardableResult
    func stop() -> Int32 {
        #if canImport(MCRustCore)
        let result = mc_rust_engine_stop()
        activeLogSink?.release()
        activeLogSink = nil
        return result
        #else
        return 0
        #endif
    }

    func resize(width: UInt32, height: UInt32, scale: Float) {
        #if canImport(MCRustCore)
        mc_rust_engine_resize(width, height, scale)
        #endif
    }

    func sendTouchInput(action: Int32, x: Float, y: Float, dx: Float, dy: Float) {
        #if canImport(MCRustCore)
        mc_rust_engine_touch_input(action, x, y, dx, dy)
        #endif
    }
}
