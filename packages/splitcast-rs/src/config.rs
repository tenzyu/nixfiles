use serde_json::Value;
use std::fs::OpenOptions;
use std::io::{self, Read};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

fn error(msg: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, msg)
}

pub fn json_string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 32 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn field<'a>(value: &'a Value, key: &str) -> io::Result<&'a Value> {
    key.trim_start_matches('.')
        .split('.')
        .try_fold(value, |v, k| {
            v.get(k)
                .ok_or_else(|| error("required configuration field missing"))
        })
}
fn get(value: &Value, key: &str) -> io::Result<String> {
    let s = field(value, key)?
        .as_str()
        .ok_or_else(|| error("configuration string required"))?;
    if s.contains(['\0', '\n', '\r']) {
        return Err(error("invalid config string"));
    }
    Ok(s.into())
}
fn number(value: &Value, key: &str, min: u16, max: u16) -> io::Result<u16> {
    let n = field(value, key)?
        .as_u64()
        .and_then(|n| u16::try_from(n).ok())
        .filter(|n| (*n >= min) && (*n <= max))
        .ok_or_else(|| error("configuration integer out of range"))?;
    Ok(n)
}
fn signed_number(value: &Value, key: &str, min: i32, max: i32) -> io::Result<i32> {
    field(value, key)?
        .as_i64()
        .and_then(|n| i32::try_from(n).ok())
        .filter(|n| *n >= min && *n <= max)
        .ok_or_else(|| error("configuration integer out of range"))
}
fn boolean(value: &Value, key: &str) -> io::Result<bool> {
    field(value, key)?
        .as_bool()
        .ok_or_else(|| error("configuration boolean required"))
}

fn valid_schema(value: &Value, schema: &Value) -> bool {
    let valid = match schema["type"].as_str() {
        Some("object") => match (value.as_object(), schema["properties"].as_object()) {
            (Some(v), Some(p)) => {
                v.len() == p.len()
                    && p.iter()
                        .all(|(k, s)| v.get(k).is_some_and(|v| valid_schema(v, s)))
            }
            _ => false,
        },
        Some("array") => value.as_array().is_some_and(|a| {
            a.len() >= schema["minItems"].as_u64().unwrap_or(0) as usize
                && a.len() <= schema["maxItems"].as_u64().unwrap_or(100) as usize
                && a.iter().all(|v| valid_schema(v, &schema["items"]))
        }),
        Some("string") => value.as_str().is_some_and(|s| {
            s.chars().count() <= schema["maxLength"].as_u64().unwrap_or(4096) as usize
                && !s.contains(['\0', '\n', '\r'])
                && schema
                    .get("pattern")
                    .and_then(Value::as_str)
                    .is_none_or(|p| {
                        regex::Regex::new(&format!("\\A(?:{p})\\z")).is_ok_and(|r| r.is_match(s))
                    })
        }),
        Some("integer") => value.as_i64().is_some_and(|n| {
            schema["minimum"].as_i64().is_none_or(|min| n >= min)
                && schema["maximum"].as_i64().is_none_or(|max| n <= max)
        }),
        Some("boolean") => value.is_boolean(),
        _ => true,
    };
    valid
        && schema.get("const").is_none_or(|v| v == value)
        && schema
            .get("enum")
            .and_then(Value::as_array)
            .is_none_or(|a| a.contains(value))
}

fn valid_routes(c: &Value) -> bool {
    let Some(routes) = c["routes"].as_array() else {
        return false;
    };
    let specs: [(&str, &str, &[&str], &[&str]); 5] = [
        (
            "game",
            "game.av",
            &["capture.gpu", "transport.rtmp"],
            &["local.headphones", "obs.game"],
        ),
        (
            "mic",
            "mic.raw",
            &["transport.rtsp", "remote.rnnoise"],
            &["obs.mic"],
        ),
        (
            "camera",
            "camera.selected",
            &["camera.hardware", "transport.rtsp"],
            &["obs.camera"],
        ),
        (
            "tts",
            "chat.text",
            &["remote.voicevox", "transport.http"],
            &["local.tts"],
        ),
        ("overlay", "overlay.text", &["obs.text"], &["obs.overlay"]),
    ];
    specs.iter().all(|(id, source, processors, targets)| {
        let mut found = routes.iter().filter(|r| r["id"].as_str() == Some(id));
        let Some(r) = found.next() else { return false };
        if found.next().is_some() {
            return false;
        }
        let mut targets = targets.to_vec();
        if *id == "tts" && c["tts"]["mix_remote"] == true {
            targets.push("obs.tts");
        }
        let enabled = match *id {
            "game" | "mic" | "overlay" => r["enabled"] == true,
            "camera" => r["enabled"] == c["camera"]["enabled"],
            "tts" => c["tts"]["enabled"] != true || r["enabled"] == true,
            _ => false,
        };
        enabled
            && r["source"].as_str() == Some(source)
            && r["processors"] == serde_json::json!(processors)
            && r["targets"] == serde_json::json!(targets)
    })
}

fn valid_connections(c: &Value) -> bool {
    let Some(url) = c["tts"]["voicevox_url"].as_str() else {
        return false;
    };
    let Some(origin) = url.strip_prefix("http://127.0.0.1") else {
        return false;
    };
    let origin = origin.strip_suffix('/').unwrap_or(origin);
    if !origin.is_empty()
        && !origin.strip_prefix(':').is_some_and(|p| {
            !p.is_empty()
                && p.bytes().all(|b| b.is_ascii_digit())
                && p.parse::<u16>().is_ok_and(|n| n > 0)
        })
    {
        return false;
    }
    let ports = [
        &c["peer"]["control_port"],
        &c["peer"]["forward_control_port"],
        &c["obs"]["websocket_port"],
        &c["capture"]["rtmp_port"],
        &c["capture"]["rtsp_port"],
        &c["capture"]["api_port"],
    ];
    if ports
        .iter()
        .enumerate()
        .any(|(i, p)| ports[..i].contains(p))
    {
        return false;
    }
    let Some(audio) = c["capture"]["game_audio"].as_str() else {
        return false;
    };
    if !audio.is_empty()
        && (!audio
            .strip_prefix("app:")
            .is_some_and(|s| !s.is_empty() && !s.contains(['|', ';', '\n', '\r', '\0']))
            || audio.eq_ignore_ascii_case("app:splitcast-tts"))
    {
        return false;
    }
    valid_routes(c)
        && (c["camera"]["enabled"] != true
            || c["camera"]["device"]
                .as_str()
                .is_some_and(|s| s.starts_with("/dev/v4l/by-id/")))
}
fn safe_name(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 256
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._:-".contains(&b))
}
pub fn is_raw_microphone(name: &str) -> bool {
    safe_name(name)
        && !["monitor", "easyeffects", "rnnoise", "splitcast"]
            .iter()
            .any(|part| name.to_ascii_lowercase().contains(part))
}
fn path(s: String) -> PathBuf {
    if s == "~" {
        return dirs_home();
    }
    if let Some(rest) = s.strip_prefix("~/") {
        return dirs_home().join(rest);
    }
    PathBuf::from(s)
}
fn dirs_home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/nonexistent"))
}

fn toml_json_compatible(value: &toml::Value) -> bool {
    match value {
        toml::Value::Datetime(_) => false,
        toml::Value::Float(n) => n.is_finite(),
        toml::Value::Array(items) => items.iter().all(toml_json_compatible),
        toml::Value::Table(items) => items.values().all(toml_json_compatible),
        _ => true,
    }
}

pub fn secret(path: &Path, max_bytes: usize) -> io::Result<String> {
    let mut file = OpenOptions::new()
        .read(true)
        .custom_flags(0x800)
        .open(path)
        .map_err(|_| error("credential unavailable"))?;
    let m = file
        .metadata()
        .map_err(|_| error("credential unavailable"))?;
    unsafe extern "C" {
        fn getuid() -> u32;
    }
    if !m.is_file() || m.mode() & 0o077 != 0 || m.uid() != unsafe { getuid() } {
        return Err(error(
            "credential must be a private file owned by this user",
        ));
    }
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take(max_bytes.saturating_add(1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| error("credential unavailable"))?;
    if bytes.len() > max_bytes {
        return Err(error("credential oversized"));
    }
    let value = std::str::from_utf8(&bytes)
        .map_err(|_| error("invalid credential"))?
        .trim();
    if value.is_empty() {
        return Err(error("credential empty"));
    }
    Ok(value.to_owned())
}

#[derive(Clone, Debug)]
pub struct Config {
    pub document: String,
    pub role: String,
    pub state_dir: PathBuf,
    pub token_file: PathBuf,
    pub remote_token_file: PathBuf,
    pub ssh_host: String,
    pub ssh_port: u16,
    pub control_port: u16,
    pub remote_control_port: u16,
    pub forward_control_port: u16,
    pub timeout: u16,
    pub retry_limit: u16,
    pub rtmp: u16,
    pub rtsp: u16,
    pub api: u16,
    pub width: u16,
    pub height: u16,
    pub fps: u16,
    pub bitrate: u16,
    pub target: String,
    pub game_audio: String,
    pub mic_source: String,
    pub tts_sink: String,
    pub processed_sink: String,
    pub rnnoise_plugin: PathBuf,
    pub rnnoise_label: String,
    pub rnnoise_control: String,
    pub gain_db: i32,
    pub mic_offset: i32,
    pub camera_enabled: bool,
    pub camera_location: String,
    pub camera_mode: String,
    pub camera_device: String,
    pub camera_encoder: String,
    pub camera_hw: PathBuf,
    pub camera_width: u16,
    pub camera_height: u16,
    pub camera_fps: u16,
    pub obs_binary: PathBuf,
    pub obs_port: u16,
    pub obs_password: PathBuf,
    pub twitch_key: PathBuf,
    pub recording_dir: PathBuf,
    pub tts_enabled: bool,
    pub voicevox_url: String,
    pub tts_speaker: u16,
    pub tts_max_text: u16,
    pub tts_queue_limit: u16,
    pub tts_expiry_seconds: u16,
    pub tts_credentials_file: PathBuf,
    pub tts_mix_remote: bool,
    pub eventsub_enabled: bool,
}
impl Config {
    pub fn load(filename: &Path) -> io::Result<Self> {
        let mut input = Vec::new();
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(0x800)
            .open(filename)?;
        if !file.metadata()?.is_file() {
            return Err(error("config must be a regular file"));
        }
        file.take(65537).read_to_end(&mut input)?;
        if input.len() > 65536 {
            return Err(error("config exceeds 64 KiB"));
        }
        if filename.extension().is_some_and(|ext| ext == "toml") {
            let text = std::str::from_utf8(&input).map_err(|_| error("invalid TOML UTF-8"))?;
            let value: toml::Value = text.parse().map_err(|_| error("invalid TOML"))?;
            if !toml_json_compatible(&value) {
                return Err(error("TOML contains unsupported value"));
            }
            let json = serde_json::to_vec(&value).map_err(|_| error("invalid TOML value"))?;
            Self::parse(&json)
        } else {
            Self::parse(&input)
        }
    }
    pub fn parse(filename: &[u8]) -> io::Result<Self> {
        if filename.len() > 65536 {
            return Err(error("config exceeds 64 KiB"));
        }
        let value: serde_json::Value =
            serde_json::from_slice(filename).map_err(|_| error("invalid JSON"))?;
        let document = serde_json::to_string(&value).map_err(|_| error("invalid JSON"))?;
        let schema: Value = serde_json::from_str(include_str!("config-schema.json"))
            .map_err(|_| error("invalid built-in schema"))?;
        if !valid_schema(&value, &schema) || !valid_connections(&value) {
            return Err(error("unsupported SplitCast config"));
        }
        let filename = &value;
        let role = get(filename, ".role")?;
        let ssh_host = get(filename, ".peer.ssh_host")?;
        if ssh_host.len() > 253
            || !ssh_host
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"._@-".contains(&b))
            || ssh_host.starts_with('-')
        {
            return Err(error("invalid ssh_host"));
        }
        let target = get(filename, ".capture.target")?;
        let game_audio = get(filename, ".capture.game_audio")?;
        let mic_source = get(filename, ".audio.mic_source")?;
        if !mic_source.is_empty() && !is_raw_microphone(&mic_source) {
            return Err(error(
                "mic_source must select a raw microphone, not a monitor or processed source",
            ));
        }
        let processed_sink = get(filename, ".audio.processed_sink")?;
        if !processed_sink.starts_with("splitcast_") || !safe_name(&processed_sink) {
            return Err(error("unsafe processed sink"));
        }
        let rnnoise_plugin = path(get(filename, ".audio.rnnoise_plugin")?);
        if !rnnoise_plugin.as_os_str().is_empty()
            && (!rnnoise_plugin.is_absolute()
                || !rnnoise_plugin
                    .to_string_lossy()
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"/._+-".contains(&b)))
        {
            return Err(error("unsafe RNNoise LADSPA path"));
        }
        let rnnoise_label = get(filename, ".audio.rnnoise_label")?;
        let rnnoise_control = get(filename, ".audio.rnnoise_control")?;
        if !safe_name(&rnnoise_label)
            || !rnnoise_control
                .bytes()
                .all(|b| b.is_ascii_digit() || b".|-".contains(&b))
        {
            return Err(error("unsafe RNNoise filter"));
        }
        let gain_db = signed_number(filename, ".audio.gain_db", -30, 20)?;
        let mic_offset = signed_number(filename, ".audio.mic_offset_ms", -2000, 2000)?;
        let camera_location = get(filename, ".camera.location")?;
        let camera_mode = get(filename, ".camera.mode")?;
        let camera_encoder = get(filename, ".camera.encoder")?;
        if !["capture", "production"].contains(&camera_location.as_str())
            || !["hardware", "h264"].contains(&camera_mode.as_str())
            || !["h264_vaapi", "h264_nvenc"].contains(&camera_encoder.as_str())
        {
            return Err(error("invalid camera mode"));
        }
        Ok(Self {
            document: document.clone(),
            role,
            ssh_host,
            state_dir: path(get(filename, ".peer.state_dir")?),
            token_file: path(get(filename, ".peer.token_file")?),
            remote_token_file: path(get(filename, ".peer.remote_token_file")?),
            ssh_port: number(filename, ".peer.ssh_port", 1, 65535)?,
            control_port: number(filename, ".peer.control_port", 1024, 65535)?,
            remote_control_port: number(filename, ".peer.remote_control_port", 1024, 65535)?,
            forward_control_port: number(filename, ".peer.forward_control_port", 1024, 65535)?,
            timeout: number(filename, ".peer.timeout_seconds", 1, 60)?,
            retry_limit: number(filename, ".peer.retry_limit", 0, 5)?,
            rtmp: number(filename, ".capture.rtmp_port", 1024, 65535)?,
            rtsp: number(filename, ".capture.rtsp_port", 1024, 65535)?,
            api: number(filename, ".capture.api_port", 1024, 65535)?,
            width: number(filename, ".capture.width", 320, 3840)?,
            height: number(filename, ".capture.height", 240, 2160)?,
            fps: number(filename, ".capture.fps", 30, 60)?,
            bitrate: number(filename, ".capture.bitrate_kbps", 1000, 50000)?,
            target,
            game_audio,
            mic_source,
            tts_sink: get(filename, ".audio.tts_sink")?,
            processed_sink,
            rnnoise_plugin,
            rnnoise_label,
            rnnoise_control,
            gain_db,
            mic_offset,
            camera_enabled: boolean(filename, ".camera.enabled")?,
            camera_location,
            camera_mode,
            camera_encoder,
            camera_device: get(filename, ".camera.device")?,
            camera_hw: path(get(filename, ".camera.hw_device")?),
            camera_width: number(filename, ".camera.width", 160, 3840)?,
            camera_height: number(filename, ".camera.height", 120, 2160)?,
            camera_fps: number(filename, ".camera.fps", 1, 60)?,
            obs_binary: path(get(filename, ".obs.binary")?),
            obs_port: number(filename, ".obs.websocket_port", 1024, 65535)?,
            obs_password: path(get(filename, ".obs.password_file")?),
            twitch_key: path(get(filename, ".obs.twitch_key_file")?),
            recording_dir: path(get(filename, ".obs.recording_dir")?),
            tts_enabled: boolean(filename, ".tts.enabled")?,
            voicevox_url: get(filename, ".tts.voicevox_url")?,
            tts_speaker: number(filename, ".tts.speaker", 0, 10000)?,
            tts_max_text: number(filename, ".tts.max_text", 1, 500)?,
            tts_queue_limit: number(filename, ".tts.queue_limit", 1, 32)?,
            tts_expiry_seconds: number(filename, ".tts.expiry_seconds", 5, 300)?,
            tts_credentials_file: path(get(filename, ".tts.credentials_file")?),
            tts_mix_remote: boolean(filename, ".tts.mix_remote")?,
            eventsub_enabled: boolean(filename, ".tts.eventsub")?,
        })
    }
    pub fn token(&self, remote: bool) -> io::Result<String> {
        let p = if remote {
            &self.remote_token_file
        } else {
            &self.token_file
        };
        let s = secret(p, 513)?;
        if s.len() < 24 || s.len() > 512 || !s.bytes().all(|b| (0x21..=0x7e).contains(&b)) {
            return Err(error("invalid secret token"));
        }
        Ok(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn toml_example_loads() {
        let file = Path::new(env!("CARGO_MANIFEST_DIR")).join("example.toml");
        let config = Config::load(&file).expect("valid TOML must load");
        let json = std::fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/example.json"))
            .unwrap();
        let expected: serde_json::Value = serde_json::from_slice(&json).unwrap();
        let actual: serde_json::Value = serde_json::from_str(&config.document).unwrap();
        assert_eq!(actual, expected);
    }

    #[test]
    fn toml_rejects_invalid_schema_and_non_json_values() {
        let example =
            std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("example.toml"))
                .unwrap();
        let file =
            std::env::temp_dir().join(format!("splitcast-config-{}.toml", std::process::id()));
        for (name, input) in [
            (
                "unknown field",
                example.replace("ssh_host =", "unknown = 1\nssh_host ="),
            ),
            (
                "wrong type",
                example.replacen("width = 1280", "width = true", 1),
            ),
            (
                "invalid route",
                example.replace("source = \"game.av\"", "source = \"mic.raw\""),
            ),
            (
                "non-finite",
                example.replacen("width = 1280", "width = inf", 1),
            ),
            (
                "datetime",
                example.replace("ssh_host = \"neko7\"", "ssh_host = 2026-01-01"),
            ),
        ] {
            std::fs::write(&file, input).unwrap();
            assert!(Config::load(&file).is_err(), "{name} must be rejected");
        }
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn json_escaping() {
        assert_eq!(json_string("a\"b\n"), "\"a\\\"b\\n\"");
    }

    #[test]
    fn preserves_strings_and_false() {
        let input = br#"{"text":"a b ","flag":false,"bad":"a\nb"}"#;
        let input: Value = serde_json::from_slice(input).unwrap();
        assert_eq!(get(&input, ".text").unwrap(), "a b ");
        assert!(!boolean(&input, ".flag").unwrap());
        assert!(get(&input, ".bad").is_err());
    }

    #[test]
    fn oversized_config_is_rejected() {
        let name = std::env::temp_dir().join(format!("splitcast-config-{}", std::process::id()));
        std::fs::write(&name, vec![b' '; 65537]).unwrap();
        let result = Config::load(&name);
        std::fs::remove_file(name).unwrap();
        assert!(result.is_err());
    }

    #[test]
    fn secret_requires_private_regular_bounded_file() {
        use std::io::Write;
        use std::os::unix::fs::PermissionsExt;
        let name =
            std::env::temp_dir().join(format!("splitcast-secret-test-{}", std::process::id()));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true).mode(0o600);
        let mut file = options.open(&name).unwrap();
        file.write_all(b"test credential\n").unwrap();
        assert_eq!(secret(&name, 16).unwrap(), "test credential");
        assert!(secret(&name, 4).is_err());
        std::fs::set_permissions(&name, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(secret(&name, 32).is_err());
        std::fs::remove_file(name).unwrap();
        assert!(secret(std::env::temp_dir().as_path(), 32).is_err());
    }
}
