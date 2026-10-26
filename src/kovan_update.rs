//! KOVAN updates.
//!
//! A manifest signed with KOVAN's own ed25519 key, published next to the
//! release assets, replaces RustDesk's update service. Downloading and
//! installing still go through the verified upstream path (size + SHA-256,
//! `update_to_verified` / `update_to_verified_dmg`).

use hbb_common::{
    anyhow::{anyhow, Context},
    base64::{engine::general_purpose::STANDARD, Engine as _},
    bail, log,
    sodiumoxide::{
        self,
        crypto::sign::{verify_detached, PublicKey, Signature},
    },
    ResultType,
};
use serde_derive::Deserialize;
use std::{collections::HashMap, path::PathBuf, sync::Mutex};

const RELEASE_PREFIX: &str = "https://github.com/olcayhizal/kovan/releases/download/kovan-nightly/";
const MANIFEST_FILE: &str = "kovan-latest.json";
const SIGNATURE_CONTEXT: &[u8] = b"KOVAN update v1\n";
const PUBLIC_KEY: [u8; 32] = [
    101, 153, 148, 163, 27, 69, 175, 197, 35, 108, 110, 128, 51, 156, 59, 198, 6, 80, 221, 117,
    66, 252, 99, 186, 121, 103, 159, 212, 183, 207, 16, 39,
];

/// Release page the Flutter update dialog uses as id and as its help link.
pub const RELEASE_PAGE: &str = "https://github.com/olcayhizal/kovan/releases/tag/kovan-nightly";
pub const EVENT_UPDATE_AVAILABLE: &str = "kovan_update_available";

static LATEST: Mutex<Option<Artifact>> = Mutex::new(None);

#[derive(Deserialize)]
struct Manifest {
    build: u32,
    artifacts: Vec<ManifestArtifact>,
}

#[derive(Deserialize)]
struct ManifestArtifact {
    platform: String,
    arch: String,
    format: String,
    url: String,
    size: u64,
    sha256: String,
}

#[derive(Clone)]
pub struct Artifact {
    pub build: u32,
    pub url: String,
    pub size: u64,
    pub sha256: String,
}

/// CI sets `KOVAN_BUILD` to the workflow run number; local builds are 0.
pub fn current_build() -> u32 {
    option_env!("KOVAN_BUILD")
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

pub fn spawn_check() {
    // Local development builds never offer updates.
    if current_build() == 0 {
        return;
    }
    std::thread::spawn(|| match check() {
        Ok(Some(artifact)) => notify(&artifact),
        Ok(None) => {}
        Err(e) => log::warn!("KOVAN update check failed: {}", e),
    });
}

/// The artifact the last check found, when `url` belongs to it.
pub fn artifact_for_url(url: &str) -> Option<Artifact> {
    LATEST
        .lock()
        .unwrap()
        .clone()
        .filter(|artifact| artifact.url == url)
}

pub fn latest() -> Option<Artifact> {
    LATEST.lock().unwrap().clone()
}

pub fn download_path(artifact: &Artifact) -> Option<PathBuf> {
    let file_name = artifact.url.strip_prefix(RELEASE_PREFIX)?;
    if file_name.is_empty() || file_name.contains(['/', '\\', ':', '?', '#']) {
        return None;
    }
    Some(std::env::temp_dir().join(format!("kovan-{}-{}", artifact.build, file_name)))
}

fn check() -> ResultType<Option<Artifact>> {
    let body = fetch(&format!("{}{}", RELEASE_PREFIX, MANIFEST_FILE))?;
    let signature = fetch(&format!("{}{}.sig", RELEASE_PREFIX, MANIFEST_FILE))?;
    verify(&body, &signature)?;
    let manifest: Manifest = serde_json::from_slice(&body).context("invalid KOVAN manifest")?;
    if manifest.build <= current_build() {
        *LATEST.lock().unwrap() = None;
        return Ok(None);
    }
    let (platform, arch, format) = target();
    let found = manifest
        .artifacts
        .into_iter()
        .find(|a| a.platform == platform && a.arch == arch && a.format == format)
        .ok_or_else(|| anyhow!("no KOVAN artifact for {}/{}/{}", platform, arch, format))?;
    let artifact = Artifact {
        build: manifest.build,
        url: found.url,
        size: found.size,
        sha256: found.sha256.to_lowercase(),
    };
    if artifact.size == 0
        || artifact.sha256.len() != 64
        || !artifact.sha256.chars().all(|c| c.is_ascii_hexdigit())
        || download_path(&artifact).is_none()
    {
        bail!("invalid KOVAN artifact in manifest");
    }
    *LATEST.lock().unwrap() = Some(artifact.clone());
    Ok(Some(artifact))
}

fn fetch(url: &str) -> ResultType<Vec<u8>> {
    let client = crate::hbbs_http::create_http_client_with_url_strict(url)?;
    let response = client.get(url).send()?;
    if !response.status().is_success() {
        bail!("{} returned HTTP {}", url, response.status());
    }
    Ok(response.bytes()?.to_vec())
}

fn verify(body: &[u8], signature: &[u8]) -> ResultType<()> {
    sodiumoxide::init().map_err(|_| anyhow!("failed to initialize sodiumoxide"))?;
    let encoded = std::str::from_utf8(signature)?.trim();
    let decoded = STANDARD
        .decode(encoded)
        .context("invalid KOVAN signature base64")?;
    let bytes: [u8; 64] = decoded
        .try_into()
        .map_err(|_| anyhow!("invalid KOVAN signature length"))?;
    let signature =
        Signature::from_bytes(&bytes).map_err(|_| anyhow!("invalid KOVAN signature bytes"))?;
    let mut signed = Vec::with_capacity(SIGNATURE_CONTEXT.len() + body.len());
    signed.extend_from_slice(SIGNATURE_CONTEXT);
    signed.extend_from_slice(body);
    if !verify_detached(&signature, &signed, &PublicKey(PUBLIC_KEY)) {
        bail!("KOVAN manifest signature does not match");
    }
    Ok(())
}

fn target() -> (&'static str, &'static str, &'static str) {
    let arch = if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else {
        "x86_64"
    };
    if cfg!(target_os = "macos") {
        ("macos", arch, "dmg")
    } else {
        ("windows", arch, "exe")
    }
}

fn notify(artifact: &Artifact) {
    #[cfg(feature = "flutter")]
    {
        let build = artifact.build.to_string();
        let data = HashMap::from([("name", EVENT_UPDATE_AVAILABLE), ("build", &build)]);
        if let Ok(data) = serde_json::to_string(&data) {
            let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, data);
        }
    }
    #[cfg(not(feature = "flutter"))]
    let _ = artifact;
}

#[cfg(test)]
mod tests {
    use super::verify;

    // Signed once with the KOVAN update key by the CI signing code path.
    const BODY: &[u8] = br#"{"build":7,"artifacts":[]}"#;
    const SIGNATURE: &[u8] =
        b"KuOr05UqYbnjIOr9rstFMIpA0SoPPJOnaA5OkA6s1Gj3QSuGUjcDPRgMengYOKczp+TS2IHUDzGR6lxNpT0BDw==\n";

    #[test]
    fn accepts_manifest_signed_with_kovan_key() {
        assert!(verify(BODY, SIGNATURE).is_ok());
    }

    #[test]
    fn rejects_tampered_manifest() {
        assert!(verify(br#"{"build":8,"artifacts":[]}"#, SIGNATURE).is_err());
    }
}
