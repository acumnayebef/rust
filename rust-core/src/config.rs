use std::path::Path;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Top-level launch configuration passed from the iOS SwiftUI launcher as JSON.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LaunchConfig {
    pub instance_id: String,
    pub instance_name: String,
    pub minecraft_version: String,
    pub instance_root: String,
    #[serde(default)]
    pub game_files_root: String,
    pub account: AccountConfig,
    pub graphics: GraphicsConfig,
    #[serde(default)]
    pub mods: Vec<ContentDescriptor>,
    #[serde(default)]
    pub shaders: Vec<ContentDescriptor>,
    #[serde(default)]
    pub resource_packs: Vec<ContentDescriptor>,
    #[serde(default)]
    pub custom_flags: Vec<String>,
}

/// Player profile metadata used by the Rust client.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountConfig {
    pub username: String,
    #[serde(default)]
    pub uuid: Option<String>,
    #[serde(default)]
    pub offline_mode: bool,
}

/// Graphics and Metal renderer tuning passed to the Rust client.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphicsConfig {
    pub render_distance: u32,
    pub max_fps: u32,
    pub vsync: bool,
    pub metalfx_upscaling: bool,
    pub shader_quality: String,
    pub touch_hud_scale: f32,
}

/// Descriptor for a single mod, shader pack, or resource pack.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentDescriptor {
    pub id: String,
    pub name: String,
    pub path: String,
    pub enabled: bool,
    #[serde(default)]
    pub order: usize,
}

/// Validation result serialized back to Swift via `mc_rust_engine_validate_config`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ValidationReport {
    pub valid: bool,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub active_mods: usize,
    pub active_shaders: usize,
    pub active_resource_packs: usize,
}

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("invalid launch JSON: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("launch configuration validation failed: {0}")]
    ValidationFailed(String),
}

impl LaunchConfig {
    /// Parses a JSON payload into a `LaunchConfig`.
    pub fn from_json(raw: &str) -> Result<Self, ConfigError> {
        Ok(serde_json::from_str(raw)?)
    }

    /// Validates instance root, player name, graphics bounds, and enabled content paths.
    pub fn validate(&self) -> ValidationReport {
        let mut errors = Vec::new();
        let mut warnings = Vec::new();

        if self.instance_id.trim().is_empty() {
            errors.push("instanceId must not be empty".to_string());
        }
        if self.minecraft_version.trim().is_empty() {
            errors.push("minecraftVersion must not be empty".to_string());
        }
        if self.account.username.trim().is_empty() {
            errors.push("account.username must not be empty".to_string());
        }
        if self.graphics.render_distance < 2 || self.graphics.render_distance > 64 {
            warnings.push(format!(
                "renderDistance ({}) is outside typical mobile range 2..=64",
                self.graphics.render_distance
            ));
        }

        let root_path = Path::new(&self.instance_root);
        if self.instance_root.trim().is_empty() {
            errors.push("instanceRoot must not be empty".to_string());
        } else if !root_path.exists() {
            errors.push(format!(
                "instanceRoot does not exist on disk: {}",
                self.instance_root
            ));
        }

        let game_files_path = Path::new(&self.game_files_root);
        if self.game_files_root.trim().is_empty() {
            errors.push("Файлы игры не импортированы. Откройте Настройки -> Импортировать файлы игры.".to_string());
        } else if !game_files_path.exists() {
            errors.push(format!(
                "Директория файлов игры не найдена: {}",
                self.game_files_root
            ));
        } else if game_files_path.is_dir() {
            let has_entries = std::fs::read_dir(game_files_path)
                .map(|mut it| it.next().is_some())
                .unwrap_or(false);
            if !has_entries {
                errors.push("Файлы игры не импортированы (папка game-files пуста).".to_string());
            }
        }

        let active_mods = validate_content_list("mod", &self.mods, &mut errors, &mut warnings);
        let active_shaders =
            validate_content_list("shader", &self.shaders, &mut errors, &mut warnings);
        let active_resource_packs = validate_content_list(
            "resourcePack",
            &self.resource_packs,
            &mut errors,
            &mut warnings,
        );

        if active_shaders > 1 {
            warnings.push(format!(
                "{active_shaders} shaders are enabled; only the first active shader pack is typically bound"
            ));
        }

        ValidationReport {
            valid: errors.is_empty(),
            errors,
            warnings,
            active_mods,
            active_shaders,
            active_resource_packs,
        }
    }
}

fn validate_content_list(
    kind: &str,
    items: &[ContentDescriptor],
    errors: &mut Vec<String>,
    warnings: &mut Vec<String>,
) -> usize {
    let mut enabled_count = 0;
    for item in items {
        if !item.enabled {
            continue;
        }
        enabled_count += 1;
        let path = Path::new(&item.path);
        if !path.exists() {
            errors.push(format!(
                "enabled {kind} '{}' is missing at path: {}",
                item.name, item.path
            ));
        } else if path.is_file() && path.metadata().map(|m| m.len() == 0).unwrap_or(false) {
            warnings.push(format!("enabled {kind} '{}' is an empty file", item.name));
        }
    }
    enabled_count
}
