use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::config::{ContentDescriptor, LaunchConfig};

/// Detected format of a mod, shader pack, or resource pack on disk.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ContentFormat {
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
