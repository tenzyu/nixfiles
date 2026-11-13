//! Serve only the generated WASM client's fixed assets. Never map URL paths to files.
use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Read};
use std::path::Path;

pub struct Assets(BTreeMap<&'static str, (&'static str, Vec<u8>)>);
impl Assets {
    pub fn load(directory: Option<&Path>) -> io::Result<Self> {
        let mut assets = BTreeMap::new();
        if let Some(directory) = directory {
            for (url, name, mime) in [
                ("/", "index.html", "text/html; charset=utf-8"),
                ("/loader.js", "loader.js", "text/javascript; charset=utf-8"),
                (
                    "/splitcast_web.js",
                    "splitcast_web.js",
                    "text/javascript; charset=utf-8",
                ),
                (
                    "/splitcast_web_bg.wasm",
                    "splitcast_web_bg.wasm",
                    "application/wasm",
                ),
            ] {
                let file = fs::File::open(directory.join(name))?;
                if !file.metadata()?.is_file() {
                    return Err(io::Error::other("WASM asset must be a regular file"));
                }
                let mut bytes = Vec::new();
                file.take(8 * 1024 * 1024 + 1).read_to_end(&mut bytes)?;
                if bytes.len() > 8 * 1024 * 1024 {
                    return Err(io::Error::other("WASM asset exceeds 8MiB"));
                }
                if name.ends_with(".wasm") && !bytes.starts_with(b"\0asm") {
                    return Err(io::Error::other("invalid WASM asset"));
                }
                assets.insert(url, (mime, bytes));
            }
        }
        Ok(Self(assets))
    }
    pub fn get(&self, path: &str) -> Option<(&str, &[u8])> {
        self.0
            .get(path)
            .map(|(mime, body)| (*mime, body.as_slice()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unavailable_assets_never_fall_back_to_request_paths() {
        let assets = Assets::load(None).unwrap();
        for path in [
            "/",
            "/../config.toml",
            "/%2e%2e/token",
            "/loader.js?token=private",
        ] {
            assert!(assets.get(path).is_none());
        }
    }
}
