pub mod config;
pub mod content;
pub mod renderer;

use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::config::LaunchConfig;
use crate::content::{inspect_manifest, ContentManifestSummary};
use crate::renderer::{CameraState, InputState, VoxelRenderer};

const CORE_VERSION_CSTR: &[u8] = b"0.1.0\0";

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

/// Integration trait for your custom Minecraft Rust Edition engine.
///
/// Replace or wrap `CustomRustClientRuntime` with your real Rust game client
/// (for example initializing a `wgpu` Metal surface from `metal_layer_ptr`).
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

/// Default reference runtime that binds `wgpu` directly to iOS `CAMetalLayer`,
/// runs a 3D procedural voxel Metal render loop, and logs loaded mods/shaders/resource packs.
pub struct CustomRustClientRuntime {
    logger: Option<Logger>,
    viewport_width: u32,
    viewport_height: u32,
    content_scale: f32,
    stop_flag: Arc<AtomicBool>,
    render_thread: Option<JoinHandle<()>>,
    pending_resize: Arc<Mutex<Option<(u32, u32)>>>,
    input_state: Arc<Mutex<InputState>>,
}

impl CustomRustClientRuntime {
    pub fn new() -> Self {
        Self {
            logger: None,
            viewport_width: 1280,
            viewport_height: 720,
            content_scale: 1.0,
            stop_flag: Arc::new(AtomicBool::new(false)),
            render_thread: None,
            pending_resize: Arc::new(Mutex::new(None)),
            input_state: Arc::new(Mutex::new(InputState::default())),
        }
    }
}

impl Default for CustomRustClientRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl EngineRuntime for CustomRustClientRuntime {
    fn start(
        &mut self,
        config: LaunchConfig,
        manifest: ContentManifestSummary,
        metal_layer_ptr: usize,
        logger: &Logger,
    ) -> Result<(), String> {
        self.logger = Some(*logger);
        self.stop_flag.store(false, Ordering::SeqCst);

        logger.info(format!(
            "Booting custom Minecraft Rust Edition runtime for instance '{}' (MC {})",
            config.instance_name, config.minecraft_version
        ));
        logger.info(format!(
            "Player '{}' | Render distance: {} chunks | Max FPS: {} | MetalFX: {}",
            config.account.username,
            config.graphics.render_distance,
            config.graphics.max_fps,
            config.graphics.metalfx_upscaling
        ));

        logger.info(format!(
            "Content pipeline ready: {} mods, {} shaders, {} resource packs",
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

        if metal_layer_ptr == 0 {
            logger.warn("CAMetalLayer pointer is null; running in headless bridge diagnostic mode");
            return Ok(());
        }

        logger.info(format!(
            "Initializing wgpu Metal renderer for CAMetalLayer 0x{metal_layer_ptr:x}..."
        ));

        let init_w = self.viewport_width.max(1);
        let init_h = self.viewport_height.max(1);
        let shader_enabled = !manifest.shaders.is_empty();

        // SAFETY: SwiftUI's `GameViewportView` keeps `CAMetalLayer` alive until `stop()` joins
        // the render thread and drops `VoxelRenderer`.
        let mut renderer = unsafe {
            VoxelRenderer::new(
                metal_layer_ptr,
                init_w,
                init_h,
                config.graphics.vsync,
                shader_enabled,
                &config.graphics.shader_quality,
            )?
        };
        logger.info("wgpu Metal 3D voxel renderer initialized successfully");

        let stop_flag = Arc::clone(&self.stop_flag);
        let pending_resize = Arc::clone(&self.pending_resize);
        let input_state = Arc::clone(&self.input_state);
        let thread_logger = *logger;
        let max_fps = config.graphics.max_fps.clamp(15, 240);
        let frame_budget = Duration::from_secs_f64(1.0 / (max_fps as f64));

        let handle = thread::Builder::new()
            .name("mc-rust-metal-render".to_string())
            .spawn(move || {
                let mut camera = CameraState::default();
                let start_time = Instant::now();
                let mut last_frame = start_time;

                while !stop_flag.load(Ordering::SeqCst) {
                    let now = Instant::now();
                    let dt = (now - last_frame).as_secs_f32().clamp(0.001, 0.05);
                    last_frame = now;

                    if let Ok(mut resize_guard) = pending_resize.lock() {
                        if let Some((w, h)) = resize_guard.take() {
                            renderer.resize(w, h);
                        }
                    }

                    if let Ok(mut input_guard) = input_state.lock() {
                        camera.update(dt, &mut input_guard);
                    }

                    let elapsed = (now - start_time).as_secs_f32();
                    if let Err(err) = renderer.render(&camera, elapsed) {
                        thread_logger.error(format!("Render frame error: {err}"));
                        break;
                    }

                    let frame_elapsed = now.elapsed();
                    if frame_elapsed < frame_budget {
                        thread::sleep(frame_budget - frame_elapsed);
                    }
                }
            })
            .map_err(|e| format!("Failed to spawn render thread: {e}"))?;

        self.render_thread = Some(handle);
        Ok(())
    }

    fn stop(&mut self, logger: &Logger) {
        self.stop_flag.store(true, Ordering::SeqCst);
        if let Some(handle) = self.render_thread.take() {
            let _ = handle.join();
        }
        logger.info(format!(
            "Stopped custom Minecraft Rust Edition runtime (last viewport={}x{} @ {}x)",
            self.viewport_width, self.viewport_height, self.content_scale
        ));
        self.logger = None;
    }

    fn resize(&mut self, width: u32, height: u32, scale: f32) {
        self.viewport_width = width;
        self.viewport_height = height;
        self.content_scale = scale;
        if let Ok(mut guard) = self.pending_resize.lock() {
            *guard = Some((width.max(1), height.max(1)));
        }
        if let Some(logger) = &self.logger {
            logger.log(
                LogLevel::Debug,
                format!("Metal drawable resized to {width}x{height} (scale={scale:.2})"),
            );
        }
    }

    fn on_touch(&mut self, action: i32, x: f32, y: f32, dx: f32, dy: f32) {
        if let Ok(mut guard) = self.input_state.lock() {
            match action {
                0 => {
                    guard.look_dx += dx;
                    guard.look_dy += dy;
                }
                3 => {
                    guard.move_x = x.clamp(-1.0, 1.0);
                    guard.move_y = y.clamp(-1.0, 1.0);
                }
                1 => {
                    if x > 0.85 && y > 0.5 {
                        guard.jump_requested = true;
                    }
                }
                _ => {}
            }
        }
        if action == 1 || action == 2 {
            if let Some(logger) = &self.logger {
                logger.log(
                    LogLevel::Debug,
                    format!("Input event action={action} pos=({x:.2}, {y:.2}) delta=({dx:.2}, {dy:.2})"),
                );
            }
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

/// Starts the Rust client runtime using `config_json` and an optional `CAMetalLayer` pointer.
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
        let mut runtime: Box<dyn EngineRuntime> = Box::new(CustomRustClientRuntime::new());

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
