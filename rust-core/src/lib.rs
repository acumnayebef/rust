pub mod config;
pub mod content;

use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::Mutex;

use libloading::Library;
use serde::Serialize;

use crate::config::LaunchConfig;
use crate::content::{inspect_game_files, inspect_manifest, ContentManifestSummary};

const CORE_VERSION_CSTR: &[u8] = b"0.2.0\0";

/// Mirrors `MCRustEngineStatus` in `include/mc_rust_core.h`.
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineStatus {
    Idle = 0,
    Validating = 1,
    Loading = 2,
    Running = 3,
    Stopping = 4,
    Error = 5,
}

/// Mirrors `MCRustLogLevel` in `include/mc_rust_core.h`.
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Debug = 0,
    Info = 1,
    Warn = 2,
    Error = 3,
}

pub type LogCallbackFn = unsafe extern "C" fn(level: i32, message: *const c_char, user_data: *mut c_void);

type ImportedGameMainFn = unsafe extern "C" fn(*const c_char, *mut c_void) -> i32;
type ImportedGameStopFn = unsafe extern "C" fn();
type ImportedGameResizeFn = unsafe extern "C" fn(u32, u32, f32);
type ImportedGameTouchFn = unsafe extern "C" fn(i32, f32, f32, f32, f32);

/// Thread-safe bridge for emitting logs back to the SwiftUI launcher console.
#[derive(Clone, Copy)]
pub struct Logger {
    callback: Option<LogCallbackFn>,
    user_data: usize,
}

impl Logger {
    fn new(callback: Option<LogCallbackFn>, user_data: *mut c_void) -> Self {
        Self {
            callback,
            user_data: user_data as usize,
        }
    }

    pub fn log(&self, level: LogLevel, message: impl AsRef<str>) {
        let Some(cb) = self.callback else {
            return;
        };
        if let Ok(c_msg) = CString::new(message.as_ref().replace('\0', " ")) {
            // SAFETY: `user_data` is supplied by the Swift host and remains alive until
            // `mc_rust_engine_stop` completes.
            unsafe {
                cb(level as i32, c_msg.as_ptr(), self.user_data as *mut c_void);
            }
        }
    }

    pub fn info(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Info, message);
    }

    pub fn warn(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Warn, message);
    }

    pub fn error(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Error, message);
    }
}

/// Integration trait for launching imported Minecraft Rust Edition / Horizon builds.
pub trait EngineRuntime: Send + Sync {
    fn start(
        &mut self,
        config: LaunchConfig,
        manifest: ContentManifestSummary,
        metal_layer_ptr: usize,
        logger: &Logger,
    ) -> Result<(), String>;

    fn stop(&mut self, logger: &Logger);

    fn resize(&mut self, width: u32, height: u32, scale: f32);

    fn on_touch(&mut self, action: i32, x: f32, y: f32, dx: f32, dy: f32);
}

/// Launches the user-imported Rust game client from `config.game_files_root`.
pub struct ImportedGameRuntime {
    logger: Option<Logger>,
    viewport_width: u32,
    viewport_height: u32,
    content_scale: f32,
    loaded_library: Option<Library>,
    stop_hook: Option<ImportedGameStopFn>,
    resize_hook: Option<ImportedGameResizeFn>,
    touch_hook: Option<ImportedGameTouchFn>,
}

impl ImportedGameRuntime {
    pub fn new() -> Self {
        Self {
            logger: None,
            viewport_width: 0,
            viewport_height: 0,
            content_scale: 1.0,
            loaded_library: None,
            stop_hook: None,
            resize_hook: None,
            touch_hook: None,
        }
    }
}

impl Default for ImportedGameRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl EngineRuntime for ImportedGameRuntime {
    fn start(
        &mut self,
        config: LaunchConfig,
        manifest: ContentManifestSummary,
        metal_layer_ptr: usize,
        logger: &Logger,
    ) -> Result<(), String> {
        self.logger = Some(*logger);
        logger.info(format!(
            "Подготовка запуска '{}' (Horizon {}) для игрока '{}'",
            config.instance_name, config.minecraft_version, config.account.username
        ));

        let game_summary = inspect_game_files(Path::new(&config.game_files_root));
        if game_summary.file_count == 0 {
            return Err(
                "Файлы игры не найдены. Импортируйте файлы игры в Настройках лаунчера."
                    .to_string(),
            );
        }

        logger.info(format!(
            "Импортированные файлы игры: {} файлов ({:.2} МБ) в {}",
            game_summary.file_count,
            (game_summary.total_bytes as f64) / (1024.0 * 1024.0),
            config.game_files_root
        ));

        logger.info(format!(
            "Активный контент Horizon: {} модов, {} шейдеров, {} ресурспаков",
            manifest.mods.len(),
            manifest.shaders.len(),
            manifest.resource_packs.len()
        ));

        for m in &manifest.mods {
            logger.info(format!("  [MOD] {} ({:?}, {} bytes)", m.name, m.format, m.size_bytes));
        }
        for s in &manifest.shaders {
            logger.info(format!(
                "  [SHADER] {} ({:?}, quality={})",
                s.name, s.format, config.graphics.shader_quality
            ));
        }
        for rp in &manifest.resource_packs {
            logger.info(format!(
                "  [RESOURCE PACK] {} ({:?}, pack_format={:?})",
                rp.name, rp.format, rp.pack_format
            ));
        }

        if let Some(dylib_path) = game_summary.dylib_entrypoint {
            logger.info(format!(
                "Обнаружен нативный модуль игры: {}",
                dylib_path.display()
            ));
            let config_json = serde_json::to_string(&config)
                .map_err(|e| format!("Failed to serialize launch config: {e}"))?;
            let config_cstr = CString::new(config_json)
                .map_err(|e| format!("Launch config contains interior NUL: {e}"))?;

            // SAFETY: Loading user-imported dynamic library inside iOS app sandbox.
            unsafe {
                let lib = Library::new(&dylib_path).map_err(|e| {
                    format!(
                        "Не удалось загрузить библиотеку {}: {e}",
                        dylib_path.display()
                    )
                })?;

                let entry: Option<ImportedGameMainFn> = lib
                    .get::<ImportedGameMainFn>(b"mc_rust_game_main\0")
                    .or_else(|_| lib.get::<ImportedGameMainFn>(b"horizon_ios_main\0"))
                    .ok()
                    .map(|sym| *sym);

                self.stop_hook = lib
                    .get::<ImportedGameStopFn>(b"mc_rust_game_stop\0")
                    .ok()
                    .map(|sym| *sym);
                self.resize_hook = lib
                    .get::<ImportedGameResizeFn>(b"mc_rust_game_resize\0")
                    .ok()
                    .map(|sym| *sym);
                self.touch_hook = lib
                    .get::<ImportedGameTouchFn>(b"mc_rust_game_touch\0")
                    .ok()
                    .map(|sym| *sym);

                if let Some(main_fn) = entry {
                    logger.info("Запуск точки входа импортированного Rust-клиента...");
                    let rc = main_fn(config_cstr.as_ptr(), metal_layer_ptr as *mut c_void);
                    if rc != 0 {
                        return Err(format!("Точка входа игры вернула код ошибки {rc}"));
                    }
                } else {
                    logger.warn("Библиотека загружена, но символ mc_rust_game_main / horizon_ios_main не найден.");
                }

                self.loaded_library = Some(lib);
            }
        } else {
            if metal_layer_ptr != 0 {
                logger.info(format!(
                    "Metal-слой 0x{metal_layer_ptr:x} привязан и ожидает запуск нативного клиента."
                ));
            }
            if !game_summary.archive_files.is_empty() {
                logger.info(format!(
                    "Обнаружены импортированные пакеты/ресурсы игры: {}",
                    game_summary.archive_files.join(", ")
                ));
            }
            logger.warn(
                "В импортированных файлах не найден .dylib с точкой входа mc_rust_game_main / horizon_ios_main — файлы проиндексированы, клиент готов к подключению.",
            );
        }

        Ok(())
    }

    fn stop(&mut self, logger: &Logger) {
        if let Some(stop_fn) = self.stop_hook.take() {
            // SAFETY: Hook belongs to `self.loaded_library` which is still alive here.
            unsafe { stop_fn() };
        }
        self.resize_hook = None;
        self.touch_hook = None;
        self.loaded_library = None;
        logger.info("Сессия импортированной игры завершена.");
        self.logger = None;
    }

    fn resize(&mut self, width: u32, height: u32, scale: f32) {
        self.viewport_width = width;
        self.viewport_height = height;
        self.content_scale = scale;
        if let Some(resize_fn) = self.resize_hook {
            // SAFETY: Hook belongs to `self.loaded_library`.
            unsafe { resize_fn(width, height, scale) };
        }
    }

    fn on_touch(&mut self, action: i32, x: f32, y: f32, dx: f32, dy: f32) {
        if let Some(touch_fn) = self.touch_hook {
            // SAFETY: Hook belongs to `self.loaded_library`.
            unsafe { touch_fn(action, x, y, dx, dy) };
        }
    }
}

struct ActiveSession {
    runtime: Box<dyn EngineRuntime>,
    logger: Logger,
}

static ENGINE_STATUS: AtomicI32 = AtomicI32::new(EngineStatus::Idle as i32);
static ACTIVE_SESSION: Mutex<Option<ActiveSession>> = Mutex::new(None);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ValidateResponse {
    valid: bool,
    errors: Vec<String>,
    warnings: Vec<String>,
    active_mods: usize,
    active_shaders: usize,
    active_resource_packs: usize,
    manifest: Option<ContentManifestSummary>,
}

fn cstr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: Caller guarantees `ptr` points to a valid null-terminated C string.
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

fn into_raw_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("{\"valid\":false,\"errors\":[\"interior NUL byte\"]}").unwrap())
        .into_raw()
}

/// Returns static null-terminated version string of the Rust bridge.
#[no_mangle]
pub extern "C" fn mc_rust_core_version() -> *const c_char {
    CORE_VERSION_CSTR.as_ptr() as *const c_char
}

/// Validates JSON launch config and returns a heap-allocated JSON report string.
#[no_mangle]
pub unsafe extern "C" fn mc_rust_engine_validate_config(config_json: *const c_char) -> *mut c_char {
    let result = catch_unwind(|| {
        let Some(raw) = cstr_to_str(config_json) else {
            let err = ValidateResponse {
                valid: false,
                errors: vec!["config_json pointer is null or invalid UTF-8".to_string()],
                warnings: vec![],
                active_mods: 0,
                active_shaders: 0,
                active_resource_packs: 0,
                manifest: None,
            };
            return into_raw_c_string(serde_json::to_string(&err).unwrap_or_default());
        };

        match LaunchConfig::from_json(raw) {
            Ok(config) => {
                let report = config.validate();
                let manifest = inspect_manifest(&config);
                let payload = ValidateResponse {
                    valid: report.valid,
                    errors: report.errors,
                    warnings: report.warnings,
                    active_mods: report.active_mods,
                    active_shaders: report.active_shaders,
                    active_resource_packs: report.active_resource_packs,
                    manifest: Some(manifest),
                };
                into_raw_c_string(serde_json::to_string(&payload).unwrap_or_default())
            }
            Err(err) => {
                let payload = ValidateResponse {
                    valid: false,
                    errors: vec![err.to_string()],
                    warnings: vec![],
                    active_mods: 0,
                    active_shaders: 0,
                    active_resource_packs: 0,
                    manifest: None,
                };
                into_raw_c_string(serde_json::to_string(&payload).unwrap_or_default())
            }
        }
    });

    result.unwrap_or_else(|_| {
        into_raw_c_string(
            "{\"valid\":false,\"errors\":[\"panic inside mc_rust_engine_validate_config\"]}"
                .to_string(),
        )
    })
}

/// Starts the imported Rust client runtime using `config_json` and a `CAMetalLayer` pointer.
#[no_mangle]
pub unsafe extern "C" fn mc_rust_engine_start(
    config_json: *const c_char,
    metal_layer: *mut c_void,
    log_cb: Option<LogCallbackFn>,
    user_data: *mut c_void,
) -> i32 {
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let logger = Logger::new(log_cb, user_data);

        let Some(raw) = cstr_to_str(config_json) else {
            logger.error("config_json pointer is null or invalid UTF-8");
            ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
            return -1;
        };

        let Ok(mut session_guard) = ACTIVE_SESSION.lock() else {
            ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
            return -2;
        };
        if session_guard.is_some() {
            logger.warn("Engine session is already active");
            return -2;
        }

        ENGINE_STATUS.store(EngineStatus::Validating as i32, Ordering::SeqCst);
        let config = match LaunchConfig::from_json(raw) {
            Ok(cfg) => cfg,
            Err(err) => {
                logger.error(format!("Failed to parse LaunchConfig JSON: {err}"));
                ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
                return -3;
            }
        };

        let report = config.validate();
        for warning in &report.warnings {
            logger.warn(warning);
        }
        if !report.valid {
            for error in &report.errors {
                logger.error(error);
            }
            ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
            return -3;
        }

        ENGINE_STATUS.store(EngineStatus::Loading as i32, Ordering::SeqCst);
        let manifest = inspect_manifest(&config);
        let mut runtime: Box<dyn EngineRuntime> = Box::new(ImportedGameRuntime::new());

        if let Err(err) = runtime.start(config, manifest, metal_layer as usize, &logger) {
            logger.error(format!("Engine failed to start: {err}"));
            ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
            return -4;
        }

        *session_guard = Some(ActiveSession { runtime, logger });
        ENGINE_STATUS.store(EngineStatus::Running as i32, Ordering::SeqCst);
        0
    }));

    outcome.unwrap_or_else(|_| {
        ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
        -5
    })
}

/// Stops the running Rust client runtime.
#[no_mangle]
pub extern "C" fn mc_rust_engine_stop() -> i32 {
    let outcome = catch_unwind(|| {
        let Ok(mut session_guard) = ACTIVE_SESSION.lock() else {
            return -1;
        };
        ENGINE_STATUS.store(EngineStatus::Stopping as i32, Ordering::SeqCst);
        if let Some(mut session) = session_guard.take() {
            session.runtime.stop(&session.logger);
        }
        ENGINE_STATUS.store(EngineStatus::Idle as i32, Ordering::SeqCst);
        0
    });

    outcome.unwrap_or_else(|_| {
        ENGINE_STATUS.store(EngineStatus::Error as i32, Ordering::SeqCst);
        -5
    })
}

/// Returns current engine status (`MCRustEngineStatus`).
#[no_mangle]
pub extern "C" fn mc_rust_engine_status() -> i32 {
    ENGINE_STATUS.load(Ordering::SeqCst)
}

/// Forwards Metal surface resize notifications to the active runtime.
#[no_mangle]
pub extern "C" fn mc_rust_engine_resize(width: u32, height: u32, scale: f32) {
    let _ = catch_unwind(|| {
        if let Ok(mut guard) = ACTIVE_SESSION.lock() {
            if let Some(session) = guard.as_mut() {
                session.runtime.resize(width, height, scale);
            }
        }
    });
}

/// Forwards touch / virtual stick input to the active runtime.
#[no_mangle]
pub extern "C" fn mc_rust_engine_touch_input(action: i32, x: f32, y: f32, dx: f32, dy: f32) {
    let _ = catch_unwind(|| {
        if let Ok(mut guard) = ACTIVE_SESSION.lock() {
            if let Some(session) = guard.as_mut() {
                session.runtime.on_touch(action, x, y, dx, dy);
            }
        }
    });
}

/// Frees strings allocated by Rust FFI functions.
#[no_mangle]
pub unsafe extern "C" fn mc_rust_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        // SAFETY: `ptr` was originally allocated with `CString::into_raw`.
        drop(CString::from_raw(ptr));
    });
}
