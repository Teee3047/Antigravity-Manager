//! Resolve browser URLs onto the Vite `dist/` tree.
//!
//! Production builds use `base: "./"` (`vite.config.ts`). A document at
//! `/accounts/` or `/settings/foo` then asks for `.../assets/...`. Those
//! files live at `dist/assets/...`. Headless hosting has to map them back
//! without changing the desktop bundle.

use std::path::{Path, PathBuf};

#[derive(Debug, PartialEq, Eq)]
pub enum StaticTarget {
    /// A real file under `dist/`.
    File(PathBuf),
    /// SPA navigation: serve `dist/index.html`.
    Index(PathBuf),
    /// Asset URL that does not exist. Do not substitute `index.html`.
    Missing,
}

pub fn resolve_static(dist: &Path, request_path: &str) -> StaticTarget {
    let rel = request_path.split('?').next().unwrap_or(request_path);
    let rel = rel.trim_start_matches('/');
    if rel.contains('\\') || rel.split('/').any(|seg| seg == "..") {
        return StaticTarget::Missing;
    }

    if rel.is_empty() {
        return index_or_missing(dist);
    }

    if let Some(path) = existing_file(dist, rel) {
        return StaticTarget::File(path);
    }

    // `/accounts/assets/index-xxxxx.js` → `dist/assets/index-xxxxx.js`
    if let Some(asset_rel) = rel.find("assets/").map(|idx| &rel[idx..]) {
        if asset_rel != rel {
            if let Some(path) = existing_file(dist, asset_rel) {
                return StaticTarget::File(path);
            }
        }
    }

    // `/accounts/icon.png` → `dist/icon.png`
    if let Some(name) = rel.rsplit('/').next() {
        if name != rel && looks_like_file(name) {
            if let Some(path) = existing_file(dist, name) {
                return StaticTarget::File(path);
            }
        }
    }

    if looks_like_file(rel) {
        StaticTarget::Missing
    } else {
        index_or_missing(dist)
    }
}

pub fn content_type(path: &Path) -> &'static str {
    match path.extension().and_then(|ext| ext.to_str()) {
        Some("html") => "text/html; charset=utf-8",
        Some("js" | "mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json" | "map") => "application/json",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("webp") => "image/webp",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("ico") => "image/x-icon",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        Some("ttf") => "font/ttf",
        Some("txt") => "text/plain; charset=utf-8",
        Some("wasm") => "application/wasm",
        _ => "application/octet-stream",
    }
}

fn looks_like_file(rel: &str) -> bool {
    match rel.rsplit('/').next() {
        Some(name) => name.contains('.') && !name.starts_with('.'),
        None => false,
    }
}

fn index_or_missing(dist: &Path) -> StaticTarget {
    match existing_file(dist, "index.html") {
        Some(path) => StaticTarget::Index(path),
        None => StaticTarget::Missing,
    }
}

fn existing_file(dist: &Path, rel: &str) -> Option<PathBuf> {
    if rel.is_empty()
        || rel
            .split('/')
            .any(|seg| seg.is_empty() || seg == "." || seg == "..")
    {
        return None;
    }
    let path = dist.join(rel);
    let root = dist.canonicalize().ok()?;
    let file = path.canonicalize().ok()?;
    if file.is_file() && file.starts_with(&root) {
        Some(file)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn fixture() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("assets")).unwrap();
        fs::write(dir.path().join("index.html"), "<html></html>").unwrap();
        fs::write(dir.path().join("icon.png"), "png").unwrap();
        fs::write(
            dir.path().join("assets").join("index-abc.js"),
            "console.log(1)",
        )
        .unwrap();
        dir
    }

    #[test]
    fn root_and_client_routes_serve_index() {
        let dir = fixture();
        assert!(matches!(
            resolve_static(dir.path(), "/"),
            StaticTarget::Index(_)
        ));
        assert!(matches!(
            resolve_static(dir.path(), "/accounts"),
            StaticTarget::Index(_)
        ));
        assert!(matches!(
            resolve_static(dir.path(), "/settings"),
            StaticTarget::Index(_)
        ));
    }

    #[test]
    fn nested_vite_assets_map_back_to_dist() {
        let dir = fixture();
        match resolve_static(dir.path(), "/accounts/assets/index-abc.js") {
            StaticTarget::File(path) => {
                assert!(
                    path.ends_with("assets/index-abc.js") || path.ends_with("assets\\index-abc.js")
                );
            }
            other => panic!("expected file, got {other:?}"),
        }
        match resolve_static(dir.path(), "/accounts/icon.png") {
            StaticTarget::File(path) => assert_eq!(path.file_name().unwrap(), "icon.png"),
            other => panic!("expected icon, got {other:?}"),
        }
        assert!(matches!(
            resolve_static(dir.path(), "/assets/index-abc.js"),
            StaticTarget::File(_)
        ));
    }

    #[test]
    fn missing_assets_do_not_fall_back_to_html() {
        let dir = fixture();
        assert_eq!(
            resolve_static(dir.path(), "/assets/missing.js"),
            StaticTarget::Missing
        );
        assert_eq!(
            resolve_static(dir.path(), "/accounts/nope.css"),
            StaticTarget::Missing
        );
    }

    #[test]
    fn parent_segments_are_rejected() {
        let dir = fixture();
        assert_eq!(
            resolve_static(dir.path(), "/../index.html"),
            StaticTarget::Missing
        );
        assert_eq!(
            resolve_static(dir.path(), "/accounts/../../etc/passwd"),
            StaticTarget::Missing
        );
        assert_eq!(
            resolve_static(dir.path(), "/assets/../../index.html"),
            StaticTarget::Missing
        );
    }
}
