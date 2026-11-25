#ifndef MC_RUST_CORE_H
#define MC_RUST_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MCRustStatusIdle = 0,
    MCRustStatusValidating = 1,
    MCRustStatusLoading = 2,
    MCRustStatusRunning = 3,
    MCRustStatusStopping = 4,
    MCRustStatusError = 5
} MCRustEngineStatus;

typedef enum {
    MCRustLogLevelDebug = 0,
    MCRustLogLevelInfo = 1,
    MCRustLogLevelWarn = 2,
    MCRustLogLevelError = 3
} MCRustLogLevel;

typedef void (*MCRustLogCallback)(int32_t level, const char *message, void *user_data);

/// Returns a static null-terminated version string for the Rust core bridge.
/// Do NOT pass this pointer to mc_rust_string_free.
const char *mc_rust_core_version(void);

/// Validates launch configuration JSON and inspects referenced mods/shaders/resource packs.
/// Returns a newly allocated JSON string describing validation status and content summary.
/// Caller must free the returned pointer with mc_rust_string_free.
char *mc_rust_engine_validate_config(const char *config_json);

/// Starts the Rust client runtime attached to the given CAMetalLayer pointer.
/// Returns 0 on success, or a negative error code on failure.
int32_t mc_rust_engine_start(
    const char *config_json,
    void *metal_layer,
    MCRustLogCallback log_cb,
    void *user_data
);

/// Stops the running Rust client runtime and releases resources.
/// Returns 0 on success, or a negative error code on failure.
int32_t mc_rust_engine_stop(void);

/// Returns current MCRustEngineStatus value.
int32_t mc_rust_engine_status(void);

/// Notifies the Rust client runtime about Metal drawable size / content scale changes.
void mc_rust_engine_resize(uint32_t width, uint32_t height, float scale);

/// Forwards touch / virtual-controller input events to the Rust client runtime.
/// action: 0 = move/look delta, 1 = press/down, 2 = release/up, 3 = virtual axis.
void mc_rust_engine_touch_input(int32_t action, float x, float y, float dx, float dy);

/// Frees a C string previously allocated by mc_rust_core (e.g. mc_rust_engine_validate_config).
void mc_rust_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* MC_RUST_CORE_H */
