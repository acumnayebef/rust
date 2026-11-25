use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::config::{ContentDescriptor, LaunchConfig};

/// Detected format of a mod, shader pack, or resource pack on disk.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ContentFormat {
    HmodArchive,
    WasmMod,
    NativeDylib,
    ZipArchive,
    JarArchive,
    Directory,
    Unknown,
}

/// Inspected metadata for a single enabled content entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InspectedContentItem {
    pub id: String,
    pub name: String,
    pub path: String,
    pub format: ContentFormat,
    pub size_bytes: u64,
    pub pack_format: Option<i64>,
    pub description: Option<String>,
}

/// Aggregated content manifest resolved right before launching the Rust client.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentManifestSummary {
    pub mods: Vec<InspectedContentItem>,
    pub shaders: Vec<InspectedContentItem>,
    pub resource_packs: Vec<InspectedContentItem>,
}

/// Summary of the imported Rust game client files on disk.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GameFilesSummary {
    pub file_count: usize,
    pub total_bytes: u64,
    pub dylib_entrypoint: Option<PathBuf>,
    pub archive_files: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct PackMcmetaRoot {
    pack: Option<PackMcmetaInfo>,
}

#[derive(Debug, Deserialize)]
struct PackMcmetaInfo {
    pack_format: Option<i64>,
    description: Option<serde_json::Value>,
}

/// Inspects all enabled mods, shader packs, and resource packs referenced by `config`.
pub fn inspect_manifest(config: &LaunchConfig) -> ContentManifestSummary {
    let mut resource_packs = inspect_group(&config.resource_packs, true);
    resource_packs.sort_by_key(|item| {
        config
            .resource_packs
            .iter()
            .find(|desc| desc.id == item.id)
            .map(|desc| desc.order)
            .unwrap_or(usize::MAX)
    });

    ContentManifestSummary {
        mods: inspect_group(&config.mods, false),
        shaders: inspect_group(&config.shaders, false),
        resource_packs,
    }
}

/// Recursively inspects the imported game files directory for executables/dylibs and assets.
pub fn inspect_game_files(root: &Path) -> GameFilesSummary {
    let mut summary = GameFilesSummary::default();
    walk_game_files(root, &mut summary, 0);
    summary
}

fn walk_game_files(dir: &Path, summary: &mut GameFilesSummary, depth: usize) {
    if depth > 6 {
        return;
    }
    if dir.is_file() {
        record_game_file(dir, summary);
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_game_files(&path, summary, depth + 1);
        } else {
            record_game_file(&path, summary);
        }
    }
}

fn record_game_file(path: &Path, summary: &mut GameFilesSummary) {
    summary.file_count += 1;
    summary.total_bytes += fs::metadata(path).map(|m| m.len()).unwrap_or(0);

    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase());

    if ext.as_deref() == Some("dylib") && summary.dylib_entrypoint.is_none() {
        summary.dylib_entrypoint = Some(path.to_path_buf());
    } else if matches!(ext.as_deref(), Some("zip" | "ipa" | "app" | "wasm" | "tar")) {
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            summary.archive_files.push(name.to_string());
        }
    }
}

fn inspect_group(items: &[ContentDescriptor], check_pack_mcmeta: bool) -> Vec<InspectedContentItem> {
    items
        .iter()
        .filter(|item| item.enabled)
        .map(|item| inspect_single(item, check_pack_mcmeta))
        .collect()
}

fn inspect_single(item: &ContentDescriptor, check_pack_mcmeta: bool) -> InspectedContentItem {
    let path = Path::new(&item.path);
    let format = detect_format(path);
    let size_bytes = fs::metadata(path).map(|m| m.len()).unwrap_or(0);

    let (pack_format, description) = if check_pack_mcmeta && path.is_dir() {
        read_pack_mcmeta(path)
    } else {
        (None, None)
    };

    InspectedContentItem {
        id: item.id.clone(),
        name: item.name.clone(),
        path: item.path.clone(),
        format,
        size_bytes,
        pack_format,
        description,
    }
}

fn detect_format(path: &Path) -> ContentFormat {
    if path.is_dir() {
        return ContentFormat::Directory;
    }

    match path
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.to_ascii_lowercase())
        .as_deref()
    {
        Some("hmod") | Some("hnmod") => ContentFormat::HmodArchive,
        Some("wasm") => ContentFormat::WasmMod,
        Some("dylib") | Some("so") => ContentFormat::NativeDylib,
        Some("zip") | Some("mcpack") => ContentFormat::ZipArchive,
        Some("jar") => ContentFormat::JarArchive,
        _ => ContentFormat::Unknown,
    }
}

fn read_pack_mcmeta(pack_dir: &Path) -> (Option<i64>, Option<String>) {
    let mcmeta_path = pack_dir.join("pack.mcmeta");
    let Ok(raw) = fs::read_to_string(mcmeta_path) else {
        return (None, None);
    };
    let Ok(parsed) = serde_json::from_str::<PackMcmetaRoot>(&raw) else {
        return (None, None);
    };
    let Some(pack) = parsed.pack else {
        return (None, None);
    };
    let desc = pack.description.map(|value| match value {
        serde_json::Value::String(s) => s,
        other => other.to_string(),
    });
    (pack.pack_format, desc)
}
