//! Native subprocess command specification. Uses the OS's existing hardware
//! codecs / GSR / FFmpeg. No game injection, no glReadPixels or frame capture
//! in the official osu! process. All arguments are passed as argv, not shell.
use crate::config::Config;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::time::{Duration, Instant};

fn strings(args: &[&str]) -> Vec<String> {
    args.iter().map(|x| x.to_string()).collect()
}
fn err(s: &str) -> io::Error {
    io::Error::other(s)
}
pub fn command_checked(argv: &[String]) -> io::Result<String> {
    let (exe, rest) = argv.split_first().ok_or_else(|| err("empty command"))?;
    let r = crate::process::run_bounded(exe, rest, None, Duration::from_secs(5), 8 * 1024 * 1024)?;
    if !r.status.success() {
        return Err(err("native helper exited nonzero; inspect its logs"));
    }
    Ok(String::from_utf8_lossy(&r.stdout).trim().to_string())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MediaObservation {
    pub ready: bool,
    pub bytes_received: u64,
    pub video_codec: Option<String>,
    pub audio_codec: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct MediaProgress {
    previous_bytes: Option<u64>,
    observed_at: Option<Instant>,
    kind: FeedKind,
}

#[derive(Clone, Copy, Debug, Default)]
pub enum FeedKind {
    #[default]
    Game,
    Mic,
    Camera,
}

pub struct ReceiveMonitor(std::collections::BTreeMap<&'static str, MediaProgress>);
impl ReceiveMonitor {
    pub fn new(camera: bool) -> Self {
        let mut feeds = std::collections::BTreeMap::from([
            ("game", MediaProgress::new(FeedKind::Game)),
            ("mic", MediaProgress::new(FeedKind::Mic)),
        ]);
        if camera {
            feeds.insert("camera", MediaProgress::new(FeedKind::Camera));
        }
        Self(feeds)
    }
    pub fn observe(&mut self, document: &str, now: Instant) -> io::Result<bool> {
        let mut healthy = true;
        for (name, progress) in &mut self.0 {
            let sample = parse_media_observation(document, name)?;
            healthy &= progress.observe_at(&sample, now);
        }
        Ok(healthy)
    }
}

pub fn receive_snapshot(cfg: &Config) -> io::Result<String> {
    run(
        "curl",
        &[
            "--disable",
            "--silent",
            "--show-error",
            "--fail",
            "--noproxy",
            "*",
            "--max-time",
            "2",
            "--max-redirs",
            "0",
            &pcm_paths(cfg),
        ],
    )
}

impl MediaObservation {
    fn usable(&self, kind: FeedKind) -> bool {
        self.ready
            && self.bytes_received > 0
            && match kind {
                FeedKind::Game => {
                    self.video_codec.as_deref() == Some("H264")
                        && self.audio_codec.as_deref() == Some("MPEG-4 Audio")
                }
                FeedKind::Mic => self.audio_codec.as_deref() == Some("Opus"),
                FeedKind::Camera => self.video_codec.as_deref() == Some("H264"),
            }
    }
}

impl MediaProgress {
    pub fn new(kind: FeedKind) -> Self {
        Self {
            kind,
            ..Self::default()
        }
    }
    pub fn observe(&mut self, sample: &MediaObservation) -> bool {
        self.observe_at(sample, Instant::now())
    }
    pub fn observe_at(&mut self, sample: &MediaObservation, now: Instant) -> bool {
        let progressing = self
            .previous_bytes
            .is_some_and(|n| sample.bytes_received > n);
        let recent = self.observed_at.is_some_and(|then| {
            now.checked_duration_since(then)
                .is_some_and(|d| d <= Duration::from_secs(3))
        });
        self.previous_bytes = Some(sample.bytes_received);
        self.observed_at = Some(now);
        sample.usable(self.kind) && progressing && recent
    }
}

pub fn parse_media_observation(json: &str, path: &str) -> io::Result<MediaObservation> {
    if json.len() > 1024 * 1024 {
        return Err(err("MediaMTX response too large"));
    }
    let document: serde_json::Value =
        serde_json::from_str(json).map_err(|_| err("invalid MediaMTX JSON"))?;
    let paths = document["items"]
        .as_array()
        .ok_or_else(|| err("MediaMTX items required"))?;
    let mut matches = paths.iter().filter(|p| p["name"].as_str() == Some(path));
    let item = matches.next().ok_or_else(|| err("media path absent"))?;
    if matches.next().is_some() {
        return Err(err("ambiguous media path"));
    }
    let ready = item["ready"]
        .as_bool()
        .ok_or_else(|| err("media readiness missing"))?;
    let bytes_received = item["bytesReceived"]
        .as_u64()
        .ok_or_else(|| err("invalid media byte counter"))?;
    let tracks = item["tracks"]
        .as_array()
        .ok_or_else(|| err("media tracks missing"))?;
    if tracks.iter().any(|v| !v.is_string()) {
        return Err(err("invalid media track"));
    }
    let video_codec = tracks
        .iter()
        .filter_map(|v| v.as_str())
        .find(|v| *v == "H264")
        .map(str::to_owned);
    let audio_codec = tracks
        .iter()
        .filter_map(|v| v.as_str())
        .find(|v| matches!(*v, "MPEG-4 Audio" | "Opus"))
        .map(str::to_owned);
    Ok(MediaObservation {
        ready,
        bytes_received,
        video_codec,
        audio_codec,
    })
}
pub fn run(exe: &str, args: &[&str]) -> io::Result<String> {
    let mut cmd = vec![exe.to_string()];
    cmd.extend(args.iter().map(|s| s.to_string()));
    command_checked(&cmd)
}
pub fn game(cfg: &Config) -> io::Result<Vec<String>> {
    if cfg.target.is_empty() || cfg.game_audio.is_empty() {
        return Err(err("explicit capture.target and game_audio required"));
    }
    if !cfg.game_audio.starts_with("app:")
        || cfg.game_audio[4..].is_empty()
        || cfg.game_audio.contains(['|', ';', '\n', '\r', '\0'])
        || cfg.game_audio.eq_ignore_ascii_case("app:splitcast-tts")
    {
        return Err(err(
            "game audio must select only the authorized game application",
        ));
    }
    let mut a = strings(&["gpu-screen-recorder", "-w"]);
    a.push(cfg.target.clone());
    a.push("-s".into());
    a.push(format!("{}x{}", cfg.width, cfg.height));
    a.extend(strings(&[
        "-f",
        &cfg.fps.to_string(),
        "-fm",
        "cfr",
        "-k",
        "h264",
        "-encoder",
        "gpu",
        "-fallback-cpu-encoding",
        "no",
        "-tune",
        "performance",
        "-bm",
        "cbr",
        "-q",
        &cfg.bitrate.to_string(),
        "-keyint",
        "2",
        "-a",
    ]));
    a.push(cfg.game_audio.clone());
    a.extend(strings(&[
        "-ac", "aac", "-ab", "192", "-cursor", "no", "-c", "flv", "-o",
    ]));
    a.push(format!("rtmp://127.0.0.1:{}/game", cfg.rtmp));
    Ok(a)
}
pub fn mic(cfg: &Config) -> io::Result<Vec<String>> {
    if cfg.mic_source.is_empty() {
        return Err(err("explicit mic_source required"));
    }
    let mut a = strings(&[
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-thread_queue_size",
        "256",
        "-f",
        "pulse",
        "-sample_rate",
        "48000",
        "-channels",
        "1",
        "-i",
    ]);
    a.push(cfg.mic_source.clone());
    a.extend(strings(&[
        "-vn",
        "-ac",
        "1",
        "-ar",
        "48000",
        "-c:a",
        "libopus",
        "-b:a",
        "96k",
        "-application",
        "lowdelay",
        "-f",
        "rtsp",
        "-rtsp_transport",
        "tcp",
    ]));
    a.push(format!("rtsp://127.0.0.1:{}/mic", cfg.rtsp));
    Ok(a)
}
pub fn rnnoise(cfg: &Config) -> io::Result<Vec<String>> {
    if cfg.processed_sink.is_empty() || !cfg.processed_sink.starts_with("splitcast_") {
        return Err(err(
            "processed audio sink must be explicitly SplitCast-owned",
        ));
    }
    let a=format!("aresample=48000:async=1000,aformat=channel_layouts=mono,ladspa=file={}:plugin={}:controls={},highpass=f=80,volume={}dB,alimiter=limit=0.95",
        cfg.rnnoise_plugin.display(),cfg.rnnoise_label,cfg.rnnoise_control,cfg.gain_db);
    Ok(vec![
        "ffmpeg".into(),
        "-hide_banner".into(),
        "-nostdin".into(),
        "-loglevel".into(),
        "error".into(),
        "-rtsp_transport".into(),
        "tcp".into(),
        "-i".into(),
        format!("rtsp://127.0.0.1:{}/mic", cfg.rtsp),
        "-vn".into(),
        "-af".into(),
        a,
        "-ar".into(),
        "48000".into(),
        "-ac".into(),
        "1".into(),
        "-f".into(),
        "pulse".into(),
        "-device".into(),
        cfg.processed_sink.clone(),
        "SplitCast processed microphone".into(),
    ])
}
pub fn camera(cfg: &Config) -> io::Result<Vec<String>> {
    if !cfg.camera_device.starts_with("/dev/v4l/by-id/")
        || cfg.camera_device.contains("..")
        || !Path::new(&cfg.camera_device).exists()
    {
        return Err(err(
            "camera device must be an existing stable /dev/v4l/by-id path",
        ));
    }
    let mut a = strings(&["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error"]);
    if cfg.camera_mode == "hardware" && cfg.camera_encoder == "h264_vaapi" {
        a.push("-vaapi_device".into());
        a.push(cfg.camera_hw.to_string_lossy().to_string());
    }
    a.extend(strings(&[
        "-f",
        "v4l2",
        "-input_format",
        if cfg.camera_mode == "h264" {
            "h264"
        } else {
            "yuyv422"
        },
        "-video_size",
        &format!("{}x{}", cfg.camera_width, cfg.camera_height),
        "-framerate",
        &cfg.camera_fps.to_string(),
        "-i",
    ]));
    a.push(cfg.camera_device.clone());
    a.push("-an".into());
    if cfg.camera_mode == "h264" {
        a.extend(strings(&["-c:v", "copy"]));
    } else {
        if cfg.camera_encoder == "h264_vaapi" {
            a.extend(strings(&["-vf", "format=nv12,hwupload"]));
        }
        a.extend(strings(&[
            "-c:v",
            &cfg.camera_encoder,
            "-b:v",
            "4M",
            "-g",
            &(cfg.camera_fps as u32 * 2).to_string(),
        ]));
    }
    a.extend(strings(&["-f", "rtsp", "-rtsp_transport", "tcp"]));
    a.push(format!("rtsp://127.0.0.1:{}/camera", cfg.rtsp));
    Ok(a)
}
pub fn tunnel(cfg: &Config) -> Vec<String> {
    let mut a = strings(&[
        "ssh",
        "-N",
        "-T",
        "-o",
        "BatchMode=yes",
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        "ServerAliveInterval=5",
        "-o",
        "ServerAliveCountMax=2",
        "-o",
        "ConnectTimeout=5",
        "-p",
        &cfg.ssh_port.to_string(),
    ]);
    for (local, remote) in [
        (cfg.forward_control_port, cfg.remote_control_port),
        (cfg.rtmp, cfg.rtmp),
        (cfg.rtsp, cfg.rtsp),
    ] {
        a.push("-L".into());
        a.push(format!("127.0.0.1:{local}:127.0.0.1:{remote}"));
    }
    a.push("--".into());
    a.push(cfg.ssh_host.clone());
    a
}
pub fn receiver(cfg: &Config) -> io::Result<Vec<String>> {
    let root = &cfg.state_dir;
    fs::create_dir_all(root)?;
    let filename = root.join("mediamtx-rs.json");
    // All ports come from bounded unsigned integers and never from user shell.
    let contents = format!(
        r#"{{"logLevel":"warn","readTimeout":"5s","writeTimeout":"5s","writeQueueSize":128,"rtsp":true,"rtspAddress":"127.0.0.1:{}","rtspTransports":["tcp"],"rtmp":true,"rtmpAddress":"127.0.0.1:{}","api":true,"apiAddress":"127.0.0.1:{}","hls":false,"webrtc":false,"srt":false,"metrics":false,"pprof":false,"playback":false,"paths":{{"game":{{"source":"publisher"}},"mic":{{"source":"publisher"}},"camera":{{"source":"publisher"}}}}}}"#,
        cfg.rtsp, cfg.rtmp, cfg.api
    );
    fs::write(&filename, contents)?;
    Ok(vec![
        "mediamtx".into(),
        filename.to_string_lossy().to_string(),
    ])
}
pub fn pcm_paths(cfg: &Config) -> String {
    format!("http://127.0.0.1:{}/v3/paths/list", cfg.api)
}

pub fn prepare_processed_sink(cfg: &Config) -> io::Result<u32> {
    let exists = run("pactl", &["-f", "json", "list", "sinks"])?;
    if exists.contains(&format!("\"name\": \"{}\"", cfg.processed_sink))
        || exists.contains(&format!("\"name\":\"{}\"", cfg.processed_sink))
    {
        return Err(err(
            "processed sink already exists; will not take ownership",
        ));
    }
    let out = run(
        "pactl",
        &[
            "load-module",
            "module-null-sink",
            &format!("sink_name={}", cfg.processed_sink),
            "rate=48000",
            "channels=1",
            "sink_properties=device.description=SplitCast_Processed_Mic",
        ],
    )?;
    out.parse::<u32>()
        .map_err(|_| err("could not identify owned Pulse module"))
}
pub fn release_processed_sink(module: u32) -> io::Result<()> {
    run("pactl", &["unload-module", &module.to_string()]).map(|_| ())
}

pub fn ready_output(buf: &str, name: &str) -> bool {
    let kind = match name {
        "game" => FeedKind::Game,
        "mic" => FeedKind::Mic,
        "camera" => FeedKind::Camera,
        _ => return false,
    };
    parse_media_observation(buf, name).is_ok_and(|o| o.usable(kind))
}
pub fn check_tools(role: &str) -> io::Result<Vec<String>> {
    let mut req = vec!["ffmpeg", "ffprobe", "pactl"];
    if role == "capture" {
        req.extend(["ssh", "gpu-screen-recorder"])
    } else {
        req.extend(["mediamtx"])
    };
    let mut missing = vec![];
    for name in req {
        let present = std::env::var_os("PATH").is_some_and(|path| {
            std::env::split_paths(&path).any(|dir| {
                let path = dir.join(name);
                path.is_file()
                    && path
                        .metadata()
                        .is_ok_and(|m| m.permissions().mode() & 0o111 != 0)
            })
        });
        if !present {
            missing.push(name.into());
        }
    }
    Ok(missing)
}
pub fn check_path(p: &Path) -> bool {
    p.is_file()
}
pub fn devices(role: &str) -> io::Result<serde_json::Value> {
    use serde_json::{json, Value};
    let mut result = json!({"role":role,"sources":[],"sinks":[],"cameras":[],"capture_targets":"","applications":"","errors":[]});
    let mut errors = Vec::new();
    for kind in ["sources", "sinks"] {
        let devices = run("pactl", &["-f", "json", "list", kind]).and_then(|s| {
            serde_json::from_str::<Value>(&s).map_err(|_| err("invalid audio discovery"))
        });
        match devices {
            Ok(Value::Array(items)) => {
                result[kind]=Value::Array(items.iter().filter_map(|v|v["name"].as_str().map(|name|json!({"name":name,"description":v["description"].as_str().unwrap_or(name)}))).collect());
            }
            _ => errors.push(format!("cannot discover Pulse {kind}")),
        }
    }
    let mut cameras = Vec::new();
    if let Ok(entries) = fs::read_dir("/dev/v4l/by-id") {
        let mut paths = entries
            .filter_map(Result::ok)
            .map(|e| e.path())
            .collect::<Vec<_>>();
        paths.sort();
        for path in paths.into_iter().take(32) {
            let device = path.to_string_lossy().into_owned();
            match run("v4l2-ctl", &["--device", &device, "--list-formats-ext"]) {
                Ok(formats) => cameras.push(json!({"device":device,"formats":formats})),
                _ => errors.push("camera enumeration failed".into()),
            }
        }
    }
    result["cameras"] = json!(cameras);
    if role == "capture" {
        for (key, option) in [
            ("capture_targets", "--list-capture-options"),
            ("applications", "--list-application-audio"),
        ] {
            match run("gpu-screen-recorder", &[option]) {
                Ok(value) => result[key] = json!(value),
                Err(_) => errors.push(format!("GSR {key} discovery unavailable")),
            }
        }
    }
    result["errors"] = json!(errors);
    Ok(result)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn readiness_requires_typed_fields_and_progress() {
        let mut progress = MediaProgress::default();
        let sample=parse_media_observation(r#"{"items":[{"name":"game","ready":true,"bytesReceived":4,"tracks":["H264","MPEG-4 Audio"]}]}"#,"game").unwrap();
        assert!(!progress.observe(&sample));
        let next=parse_media_observation(r#"{"items":[{"name":"game","ready":true,"bytesReceived":5,"tracks":["H264","MPEG-4 Audio"]}]}"#,"game").unwrap();
        assert!(progress.observe(&next));
        assert!(!progress.observe(&next));
    }
    #[test]
    fn a_path_name_is_not_readiness() {
        assert!(!ready_output(r#"{"items":[{"name":"game"}]}"#, "game"));
    }
    #[test]
    fn microphone_readiness_does_not_require_a_video_track() {
        assert!(
            ready_output(
                r#"{"items":[{"name":"mic","ready":true,"bytesReceived":42,"tracks":["Opus"]}]}"#,
                "mic"
            ),
            "valid audio-only microphone feed was refused"
        );
    }
}
