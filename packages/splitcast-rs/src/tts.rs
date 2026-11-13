use crate::{config::Config, process::run_bounded};
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const AUDIO_LIMIT: usize = 4 * 1024 * 1024;
const QUERY_LIMIT: usize = 256 * 1024;

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}
fn safe_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}
fn encode(text: &str) -> String {
    let mut out = String::new();
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}
fn origin(url: &str) -> io::Result<String> {
    let rest = url
        .strip_prefix("http://127.0.0.1:")
        .ok_or_else(|| invalid("VOICEVOX must use http://127.0.0.1:PORT"))?;
    let port = rest.strip_suffix('/').unwrap_or(rest);
    if port.is_empty()
        || !port.bytes().all(|b| b.is_ascii_digit())
        || port.parse::<u16>().ok().filter(|p| *p > 0).is_none()
    {
        return Err(invalid("invalid VOICEVOX port"));
    }
    Ok(format!("http://127.0.0.1:{port}"))
}
fn wav(data: &[u8]) -> io::Result<()> {
    if data.len() > AUDIO_LIMIT
        || data.len() < 12
        || &data[..4] != b"RIFF"
        || &data[8..12] != b"WAVE"
    {
        return Err(invalid("invalid WAV"));
    }
    let u32at = |i: usize| u32::from_le_bytes(data[i..i + 4].try_into().unwrap()) as usize;
    if u32at(4).checked_add(8) != Some(data.len()) {
        return Err(invalid("invalid WAV length"));
    }
    let mut pos = 12;
    let mut fmt = None;
    let mut frames = None;
    while pos + 8 <= data.len() {
        let len = u32at(pos + 4);
        let start = pos + 8;
        let end = start
            .checked_add(len)
            .filter(|end| *end <= data.len())
            .ok_or_else(|| invalid("truncated WAV"))?;
        if &data[pos..pos + 4] == b"fmt " && len >= 16 {
            let u16at = |i: usize| u16::from_le_bytes(data[i..i + 2].try_into().unwrap());
            fmt = Some((
                u16at(start),
                u16at(start + 2),
                u32at(start + 4),
                u16at(start + 14),
            ));
        } else if &data[pos..pos + 4] == b"data" {
            frames = Some(len);
        }
        pos = end
            .checked_add(len % 2)
            .ok_or_else(|| invalid("invalid WAV"))?;
    }
    if pos != data.len() {
        return Err(invalid("invalid WAV chunks"));
    }
    let (format, channels, rate, bits) = fmt.ok_or_else(|| invalid("missing WAV format"))?;
    let len = frames.ok_or_else(|| invalid("missing WAV data"))?;
    if format != 1
        || !(1..=2).contains(&channels)
        || !(8000..=48000).contains(&rate)
        || bits != 16
        || len == 0
        || len % (channels as usize * 2) != 0
        || len / (channels as usize * 2) > rate * 30
    {
        return Err(invalid("WAV must be bounded PCM16"));
    }
    Ok(())
}
fn post(url: String, input: Option<&[u8]>, cap: usize) -> io::Result<Vec<u8>> {
    let mut args: Vec<String> = [
        "--disable",
        "--silent",
        "--show-error",
        "--fail",
        "--noproxy",
        "*",
        "--proto",
        "=http",
        "--max-redirs",
        "0",
        "--max-time",
        "15",
        "--request",
        "POST",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    if input.is_some() {
        args.extend([
            "--header".into(),
            "Content-Type: application/json".into(),
            "--data-binary".into(),
            "@-".into(),
        ]);
    }
    args.extend(["--".into(), url]);
    let result = run_bounded("curl", &args, input, Duration::from_secs(16), cap)?;
    if !result.status.success() {
        return Err(io::Error::other("VOICEVOX request failed"));
    }
    Ok(result.stdout)
}

struct Job {
    id: String,
    text: String,
    expires: Instant,
    expires_epoch: f64,
    path: Option<PathBuf>,
    attempts: u8,
}

pub struct Speech {
    root: String,
    speaker: u16,
    max_text: usize,
    limit: usize,
    expiry: Duration,
    cache: PathBuf,
    enabled: bool,
    muted: bool,
    pending: VecDeque<Job>,
    ready: VecDeque<Job>,
    playing: Option<Job>,
    seen: VecDeque<String>,
    error: String,
    serial: u64,
}
impl Speech {
    pub fn new(cfg: &Config) -> io::Result<Self> {
        let root = origin(&cfg.voicevox_url)?;
        let cache = cfg.state_dir.join("tts-audio");
        fs::DirBuilder::new()
            .mode(0o700)
            .create(&cache)
            .or_else(|e| {
                if e.kind() == io::ErrorKind::AlreadyExists {
                    Ok(())
                } else {
                    Err(e)
                }
            })?;
        let meta = fs::symlink_metadata(&cache)?;
        unsafe extern "C" {
            fn getuid() -> u32;
        }
        if !meta.is_dir() || meta.uid() != unsafe { getuid() } || meta.mode() & 0o077 != 0 {
            return Err(invalid(
                "TTS cache directory must be private and owned by this user",
            ));
        }
        Ok(Self {
            root,
            speaker: cfg.tts_speaker,
            max_text: cfg.tts_max_text as usize,
            limit: cfg.tts_queue_limit as usize,
            expiry: Duration::from_secs(cfg.tts_expiry_seconds as u64),
            cache,
            enabled: cfg.tts_enabled,
            muted: false,
            pending: VecDeque::new(),
            ready: VecDeque::new(),
            playing: None,
            seen: VecDeque::new(),
            error: String::new(),
            serial: 0,
        })
    }
    fn remove(job: Job) {
        if let Some(path) = job.path {
            let _ = fs::remove_file(path);
        }
    }
    fn expire(&mut self) {
        let now = Instant::now();
        let mut kept = VecDeque::new();
        while let Some(job) = self.pending.pop_front() {
            if job.expires > now {
                kept.push_back(job);
            } else {
                Self::remove(job);
            }
        }
        self.pending = kept;
        let mut kept = VecDeque::new();
        while let Some(job) = self.ready.pop_front() {
            if job.expires > now {
                kept.push_back(job);
            } else {
                Self::remove(job);
            }
        }
        self.ready = kept;
        if self.playing.as_ref().is_some_and(|j| j.expires <= now) {
            Self::remove(self.playing.take().unwrap());
        }
    }
    pub fn enqueue(&mut self, text: &str, id: &str) -> io::Result<Value> {
        self.expire();
        if !safe_id(id) {
            return Err(invalid("invalid speech ID"));
        }
        if self.seen.iter().any(|v| v == id) {
            return Ok(json!({"id":id,"duplicate":true}));
        }
        let text = text.trim();
        if text.is_empty()
            || text.chars().count() > self.max_text
            || text.chars().any(|c| c < ' ' && c != '\n')
        {
            return Err(invalid("invalid speech text"));
        }
        if !self.enabled || self.muted {
            return Err(invalid("TTS is disabled or muted"));
        }
        if self.pending.len() + self.ready.len() + usize::from(self.playing.is_some()) >= self.limit
        {
            return Err(invalid("TTS queue is full"));
        }
        let now = Instant::now();
        let epoch = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();
        self.pending.push_back(Job {
            id: id.into(),
            text: text.into(),
            expires: now + self.expiry,
            expires_epoch: epoch + self.expiry.as_secs_f64(),
            path: None,
            attempts: 0,
        });
        self.seen.push_back(id.into());
        if self.seen.len() > 1024 {
            self.seen.pop_front();
        }
        Ok(json!({"id":id,"duplicate":false}))
    }
    fn synthesize(&mut self, job: &Job) -> io::Result<PathBuf> {
        let query = post(
            format!(
                "{}/audio_query?text={}&speaker={}",
                self.root,
                encode(&job.text),
                self.speaker
            ),
            None,
            QUERY_LIMIT,
        )?;
        let _: Value =
            serde_json::from_slice(&query).map_err(|_| invalid("invalid audio query JSON"))?;
        let audio = post(
            format!("{}/synthesis?speaker={}", self.root, self.speaker),
            Some(&query),
            AUDIO_LIMIT,
        )?;
        wav(&audio)?;
        self.serial += 1;
        let name = format!("{}-{}-{}", std::process::id(), self.serial, job.id);
        let tmp = self.cache.join(format!(".{name}.tmp"));
        let path = self.cache.join(format!("{name}.wav"));
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&tmp)?;
            file.write_all(&audio)?;
            file.sync_all()?;
            fs::rename(&tmp, &path)?;
            Ok(path)
        })();
        if result.is_err() {
            let _ = fs::remove_file(tmp);
        }
        result
    }
    /// Performs at most one bounded synthesis attempt. Call outside latency-sensitive handlers.
    pub fn tick(&mut self) {
        self.expire();
        if !self.enabled || self.muted {
            return;
        }
        let Some(mut job) = self.pending.pop_front() else {
            return;
        };
        job.attempts += 1;
        match self.synthesize(&job) {
            Ok(path) => {
                job.path = Some(path);
                if job.expires > Instant::now() {
                    self.ready.push_back(job);
                    self.error.clear();
                } else {
                    Self::remove(job);
                }
            }
            Err(_) => {
                self.error = "VOICEVOX synthesis failed".into();
                if job.attempts < 3 && job.expires > Instant::now() {
                    self.pending.push_front(job);
                }
            }
        }
    }
    pub fn next(&mut self) -> Value {
        self.expire();
        if !self.enabled || self.muted || self.playing.is_some() {
            return Value::Null;
        }
        self.ready
            .front()
            .map(|j| json!({"id":j.id,"expires":j.expires_epoch}))
            .unwrap_or(Value::Null)
    }
    pub fn audio(&mut self, id: &str) -> io::Result<PathBuf> {
        self.expire();
        if !safe_id(id) || !self.enabled || self.muted {
            return Err(invalid("speech unavailable"));
        }
        self.ready
            .iter()
            .find(|j| j.id == id)
            .and_then(|j| j.path.clone())
            .ok_or_else(|| invalid("speech unavailable"))
    }
    pub fn ack(&mut self, id: &str) -> Value {
        self.expire();
        if self.enabled && !self.muted && self.playing.is_none() {
            if let Some(pos) = self.ready.iter().position(|j| j.id == id) {
                self.playing = self.ready.remove(pos);
            }
        }
        json!({"acknowledged":id})
    }
    pub fn finished(&mut self, id: &str) -> Value {
        if self.playing.as_ref().is_some_and(|j| j.id == id) {
            Self::remove(self.playing.take().unwrap());
        }
        json!({"finished":id})
    }
    pub fn command(&mut self, action: &str, args: &[String]) -> io::Result<Value> {
        self.expire();
        match action {
            "say" => {
                let text = args
                    .first()
                    .ok_or_else(|| invalid("speech text required"))?;
                self.serial += 1;
                let id = format!(
                    "local-{}-{}-{}",
                    std::process::id(),
                    SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_nanos(),
                    self.serial
                );
                return self.enqueue(text, &id);
            }
            "on" => self.enabled = true,
            "unmute" => self.muted = false,
            "off" | "mute" | "clear" => {
                if action == "off" {
                    self.enabled = false;
                }
                if action == "mute" {
                    self.muted = true;
                }
                while let Some(job) = self.pending.pop_front() {
                    Self::remove(job);
                }
                while let Some(job) = self.ready.pop_front() {
                    Self::remove(job);
                }
                if let Some(job) = self.playing.take() {
                    Self::remove(job);
                }
            }
            "skip" => {
                if let Some(job) = self
                    .playing
                    .take()
                    .or_else(|| self.ready.pop_front())
                    .or_else(|| self.pending.pop_front())
                {
                    Self::remove(job);
                }
            }
            "status" => (),
            _ => return Err(invalid("unknown TTS command")),
        }
        Ok(
            json!({"enabled":self.enabled,"muted":self.muted,"pending":self.pending.len(),"ready":self.ready.len(),"active":false,"playing":self.playing.as_ref().map(|j| &j.id),"error":self.error}),
        )
    }
}
impl Drop for Speech {
    fn drop(&mut self) {
        while let Some(job) = self.ready.pop_front() {
            Self::remove(job);
        }
        if let Some(job) = self.playing.take() {
            Self::remove(job);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    fn setup(root: String) -> Speech {
        let cache = std::env::temp_dir().join(format!(
            "splitcast-tts-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::DirBuilder::new().mode(0o700).create(&cache).unwrap();
        Speech {
            root,
            speaker: 1,
            max_text: 50,
            limit: 2,
            expiry: Duration::from_secs(5),
            cache,
            enabled: true,
            muted: false,
            pending: VecDeque::new(),
            ready: VecDeque::new(),
            playing: None,
            seen: VecDeque::new(),
            error: String::new(),
            serial: 0,
        }
    }
    fn sample_wav() -> Vec<u8> {
        let mut v = b"RIFF".to_vec();
        v.extend(38u32.to_le_bytes());
        v.extend(b"WAVEfmt ");
        v.extend(16u32.to_le_bytes());
        v.extend(1u16.to_le_bytes());
        v.extend(1u16.to_le_bytes());
        v.extend(8000u32.to_le_bytes());
        v.extend(16000u32.to_le_bytes());
        v.extend(2u16.to_le_bytes());
        v.extend(16u16.to_le_bytes());
        v.extend(b"data");
        v.extend(2u32.to_le_bytes());
        v.extend([0, 0]);
        v
    }
    #[test]
    fn synthesis_claim_and_replay() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let root = format!("http://{}", listener.local_addr().unwrap());
        let handle = thread::spawn(move || {
            let mut requests = Vec::new();
            for n in 0..2 {
                let (mut stream, _) = listener.accept().unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_secs(3)))
                    .unwrap();
                let mut bytes = Vec::new();
                let mut buf = [0u8; 4096];
                loop {
                    let count = stream.read(&mut buf).unwrap();
                    if count == 0 {
                        break;
                    }
                    bytes.extend_from_slice(&buf[..count]);
                    if let Some(end) = bytes.windows(4).position(|x| x == b"\r\n\r\n") {
                        let headers = String::from_utf8_lossy(&bytes[..end]);
                        let len = headers
                            .lines()
                            .find_map(|line| {
                                line.to_ascii_lowercase()
                                    .strip_prefix("content-length:")
                                    .and_then(|v| v.trim().parse::<usize>().ok())
                            })
                            .unwrap_or(0);
                        if bytes.len() >= end + 4 + len {
                            break;
                        }
                    }
                }
                requests.push(String::from_utf8_lossy(&bytes).into_owned());
                let body = if n == 0 {
                    b"{\"query\":true}".to_vec()
                } else {
                    sample_wav()
                };
                write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                )
                .unwrap();
                stream.write_all(&body).unwrap();
            }
            requests
        });
        let mut s = setup(root);
        assert_eq!(
            s.enqueue("hello & 世界", "abc").unwrap()["duplicate"],
            false
        );
        assert_eq!(s.enqueue("hello", "abc").unwrap()["duplicate"], true);
        s.tick();
        let req = handle.join().unwrap();
        assert!(req[0]
            .starts_with("POST /audio_query?text=hello%20%26%20%E4%B8%96%E7%95%8C&speaker=1 "));
        assert!(req[1].ends_with("{\"query\":true}"));
        assert_eq!(s.next()["id"], "abc");
        let path = s.audio("abc").unwrap();
        assert_eq!(fs::read(&path).unwrap(), sample_wav());
        assert_eq!(fs::metadata(&path).unwrap().mode() & 0o777, 0o600);
        s.ack("abc");
        assert!(s.next().is_null());
        assert!(s.audio("abc").is_err());
        s.finished("abc");
        assert!(!path.exists());
        assert_eq!(s.enqueue("again", "abc").unwrap()["duplicate"], true);
        let cache = s.cache.clone();
        drop(s);
        fs::remove_dir(cache).unwrap();
    }
    #[test]
    fn capacity_expiry_skip_mute_and_failure() {
        let mut s = setup("http://127.0.0.1:1".into());
        s.enqueue("a", "a").unwrap();
        s.enqueue("b", "b").unwrap();
        assert!(s.enqueue("c", "c").is_err());
        s.command("skip", &[]).unwrap();
        s.enqueue("c", "c").unwrap();
        s.pending.front_mut().unwrap().expires = Instant::now();
        assert_eq!(s.command("status", &[]).unwrap()["pending"], 1);
        for _ in 0..4 {
            s.tick();
        }
        assert!(s.next().is_null());
        assert_eq!(s.command("status", &[]).unwrap()["pending"], 0);
        assert_eq!(s.enqueue("c", "c").unwrap()["duplicate"], true);
        s.command("mute", &[]).unwrap();
        assert!(s.enqueue("d", "d").is_err());
        s.command("unmute", &[]).unwrap();
        assert!(s.enqueue("d", "../bad").is_err());
        s.command("clear", &[]).unwrap();
        let cache = s.cache.clone();
        drop(s);
        fs::remove_dir(cache).unwrap();
    }
    #[test]
    fn rejects_non_loopback_and_invalid_wav() {
        for url in [
            "http://localhost:50021",
            "http://127.0.0.2:80",
            "http://127.0.0.1:1@evil",
            "http://127.0.0.1:1/path",
            "https://127.0.0.1:1",
            "http://127.0.0.1:0",
        ] {
            assert!(origin(url).is_err(), "{url}");
        }
        assert!(origin("http://127.0.0.1:50021/").is_ok());
        assert!(wav(&sample_wav()).is_ok());
        assert!(wav(b"RIFFxxxxWAVE").is_err());
    }
}
