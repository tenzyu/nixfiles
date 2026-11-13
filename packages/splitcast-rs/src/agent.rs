//! Native Rust SplitCast control-plane candidate. No Python subprocesses or
//! dependency on osu! code. The production cutover remains explicitly gated
//! until existing negative/media/OBS/TTS/EventSub tests pass on both hosts.
use crate::protocol::{Command, Invocation, MicAction};
use crate::{config, control, media, obs};
use crate::{Lifecycle, Output, OwnedProcess, Role, Session};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Read};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    mpsc, Arc,
};
use std::thread;
use std::time::{Duration, Instant};

static SHUTDOWN: AtomicBool = AtomicBool::new(false);
unsafe extern "C" {
    fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
    fn flock(fd: i32, operation: i32) -> i32;
    fn getuid() -> u32;
}
extern "C" fn shutdown(_: i32) {
    SHUTDOWN.store(true, Ordering::Relaxed);
}

fn err(s: &str) -> io::Error {
    io::Error::other(s)
}
fn json_state(s: Lifecycle) -> &'static str {
    match s {
        Lifecycle::Idle => "idle",
        Lifecycle::Preparing => "preparing",
        Lifecycle::Ready => "ready",
        Lifecycle::Running => "running",
        Lifecycle::Degraded => "degraded",
        Lifecycle::Stopping => "stopping",
        Lifecycle::Failed => "failed",
    }
}
fn rand_hex() -> io::Result<String> {
    let mut bytes = [0u8; 16];
    let mut f = fs::File::open("/dev/urandom")?;
    f.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|x| format!("{x:02x}")).collect::<String>())
}
fn merge_settings(document: &mut Value, patch: &Value) -> io::Result<()> {
    let patch = patch
        .as_object()
        .ok_or_else(|| err("settings object required"))?;
    for (section, fields) in patch {
        let fields = fields
            .as_object()
            .ok_or_else(|| err("settings section object required"))?;
        if document.get(section).is_none() {
            document[section] = json!({});
        }
        let target = document[section]
            .as_object_mut()
            .ok_or_else(|| err("settings section object required"))?;
        for (key, value) in fields {
            target.insert(key.clone(), value.clone());
        }
    }
    Ok(())
}
fn apply_settings(cfg: &config::Config, patch: &Value) -> io::Result<config::Config> {
    let mut document: Value =
        serde_json::from_str(&cfg.document).map_err(|_| err("invalid normalized configuration"))?;
    for (section, fields) in patch
        .as_object()
        .ok_or_else(|| err("settings object required"))?
    {
        let allowed: &[&str] = match section.as_str() {
            "peer" => &["ssh_host"],
            "capture" => &["target", "game_audio"],
            "audio" => &["mic_source", "tts_sink", "mic_offset_ms"],
            "camera" => &[
                "enabled",
                "location",
                "device",
                "mode",
                "encoder",
                "hw_device",
                "width",
                "height",
                "fps",
                "offset_ms",
            ],
            "tts" => &["enabled", "mix_remote", "eventsub"],
            _ => return Err(err("unsupported selection section")),
        };
        if fields
            .as_object()
            .ok_or_else(|| err("settings section object required"))?
            .keys()
            .any(|key| !allowed.contains(&key.as_str()))
        {
            return Err(err("unsupported selection field"));
        }
    }
    merge_settings(&mut document, patch)?;
    let enabled = document["camera"]["enabled"].clone();
    let mix = document["tts"]["mix_remote"] == true;
    for route in document["routes"]
        .as_array_mut()
        .ok_or_else(|| err("routes missing"))?
    {
        if route["id"] == "camera" {
            route["enabled"] = enabled.clone();
        }
        if route["id"] == "tts" {
            route["targets"] = if mix {
                json!(["local.tts", "obs.tts"])
            } else {
                json!(["local.tts"])
            };
        }
    }
    config::Config::parse(document.to_string().as_bytes())
}
fn transport(cfg: &config::Config) -> Value {
    json!({"version":1,"video":{"codec":"H264","width":cfg.width,"height":cfg.height,"fps":cfg.fps},"audio":{"game":"MPEG-4 Audio","mic":"Opus","rate":48000},"ports":{"rtmp":cfg.rtmp,"rtsp":cfg.rtsp}})
}
pub fn doctor(cfg: &config::Config) -> io::Result<String> {
    let missing = media::check_tools(&cfg.role)?;
    Ok(json!({"ok":missing.is_empty(),"engine":"rust-candidate","missing":missing,"capture_target_selected":!cfg.target.is_empty(),"game_only_audio_selected":cfg.game_audio.starts_with("app:"),"rnnoise_plugin_present":cfg.rnnoise_plugin.is_file(),"competitive_non_regression":"NOT VERIFIED","cutover_authorized":false}).to_string())
}
struct Agent {
    cfg: config::Config,
    session: Session,
    children: BTreeMap<String, OwnedProcess>,
    owned_module: Option<u32>,
    owner: String,
    lease: Option<(String, Instant)>,
    error: String,
    warnings: Vec<String>,
    mic_muted: bool,
    last_heartbeat: Instant,
    _lock: fs::File,
    speech: Option<crate::tts::Speech>,
    receive_monitor: Option<media::ReceiveMonitor>,
    last_health: Instant,
    output_observation: Option<obs::OutputStatus>,
}
impl Agent {
    fn new(mut cfg: config::Config) -> io::Result<Self> {
        let role = if cfg.role == "capture" {
            Role::Capture
        } else {
            Role::Production
        };
        cfg.state_dir = cfg.state_dir.join(&cfg.role);
        let directory = crate::state::private_directory(&cfg.state_dir)?;
        let lock = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .custom_flags(0x20000 | 0x800)
            .open(
                std::path::PathBuf::from(format!("/proc/self/fd/{}", directory.as_raw_fd()))
                    .join("agent.lock"),
            )?;
        let meta = lock.metadata()?;
        if !meta.is_file() || meta.uid() != unsafe { getuid() } || meta.mode() & 0o077 != 0 {
            return Err(err("unsafe state lock file"));
        }
        if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
            return Err(err("an agent already owns this role state directory"));
        }
        let saved = cfg.state_dir.join("settings.json");
        if saved.exists() {
            let patch: Value = serde_json::from_str(&config::secret(&saved, 65536)?)
                .map_err(|_| err("invalid saved selections"))?;
            let mut selected = apply_settings(&cfg, &patch)?;
            selected.state_dir = cfg.state_dir.clone();
            cfg = selected;
        }
        Ok(Self {
            cfg,
            session: Session::new(role),
            children: BTreeMap::new(),
            owned_module: None,
            owner: rand_hex()?,
            lease: None,
            error: String::new(),
            warnings: vec![],
            mic_muted: false,
            last_heartbeat: Instant::now(),
            _lock: lock,
            speech: None,
            receive_monitor: None,
            last_health: Instant::now(),
            output_observation: None,
        })
    }
    fn status(&self) -> String {
        let list = self
            .children
            .keys()
            .map(|k| config::json_string(k))
            .collect::<Vec<_>>()
            .join(",");
        let notices = self
            .warnings
            .iter()
            .map(|x| config::json_string(x))
            .collect::<Vec<_>>()
            .join(",");
        let out = self
            .session
            .output()
            .map(|x| config::json_string(x.as_str()))
            .unwrap_or_else(|| "null".into());
        format!("{{\"version\":1,\"engine\":\"rust-candidate\",\"role\":{},\"state\":{},\"output\":{out},\"error\":{},\"warnings\":[{notices}],\"mic_muted\":{},\"children\":[{list}]}}",config::json_string(&self.cfg.role),config::json_string(json_state(self.session.state())),config::json_string(&self.error),self.mic_muted)
    }
    fn spawn(&mut self, name: &str, argv: Vec<String>) -> io::Result<()> {
        if self.children.contains_key(name) {
            return Err(err("child already owned"));
        }
        let child = OwnedProcess::spawn(&argv)?;
        self.children.insert(name.into(), child);
        Ok(())
    }
    fn wait_ready<F>(&self, mut check: F) -> io::Result<()>
    where
        F: FnMut() -> bool,
    {
        let end = Instant::now() + Duration::from_secs(self.cfg.timeout as u64);
        while Instant::now() < end {
            if check() {
                return Ok(());
            }
            thread::sleep(Duration::from_millis(200));
        }
        Err(err("external service readiness timeout"))
    }
    fn guard_lease(&self, owner: Option<&str>) -> io::Result<()> {
        if self.session.state() != Lifecycle::Idle
            && self.lease.as_ref().map(|(held, _)| held.as_str()) != owner
        {
            return Err(err(
                "session is already owned; stop it locally before changing owners",
            ));
        }
        Ok(())
    }
    fn renew_lease(&mut self, owner: &str) -> io::Result<()> {
        if self.cfg.role != "production"
            || !matches!(
                self.session.state(),
                Lifecycle::Ready | Lifecycle::Running | Lifecycle::Degraded
            )
            || !self
                .lease
                .as_ref()
                .is_some_and(|(held, when)| held == owner && Instant::now() < *when)
        {
            return Err(err(
                "no matching active production owner; prepare a new session",
            ));
        }
        self.lease = Some((
            owner.into(),
            Instant::now() + Duration::from_secs((self.cfg.timeout as u64 * 8).max(30)),
        ));
        Ok(())
    }
    fn prepare(&mut self, owner: Option<&str>) -> io::Result<()> {
        self.guard_lease(owner)?;
        if matches!(self.session.state(), Lifecycle::Ready | Lifecycle::Running) {
            return Ok(());
        }
        if self.session.state() != Lifecycle::Idle {
            return Err(err("stop before preparing another session"));
        }
        self.session
            .prepare()
            .map_err(|_| err("invalid prepare transition"))?;
        let outcome = (|| -> io::Result<()> {
            let missing = media::check_tools(&self.cfg.role)?;
            if !missing.is_empty() {
                return Err(err("SplitCast required native tools missing"));
            }
            if self.cfg.role == "capture" {
                self.spawn("ssh", media::tunnel(&self.cfg))?;
                self.wait_ready(|| control::request_peer(&self.cfg, "status", "{}").is_ok())?;
                control::request_peer(
                    &self.cfg,
                    "prepare",
                    &format!("{{\"_owner\":{}}}", config::json_string(&self.owner)),
                )?;
            } else {
                self.spawn("mediamtx", media::receiver(&self.cfg)?)?;
                self.wait_ready(|| {
                    media::run(
                        "curl",
                        &["-fsS", "--max-time", "2", &media::pcm_paths(&self.cfg)],
                    )
                    .is_ok()
                })?;
                self.owned_module = Some(media::prepare_processed_sink(&self.cfg)?);
                self.spawn("obs", obs::launch_args(&self.cfg)?)?;
                self.wait_ready(|| obs::Obs::connect(&self.cfg).is_ok())?;
                let mut o = obs::Obs::connect(&self.cfg)?;
                o.configure(&self.cfg)?;
                self.speech = Some(crate::tts::Speech::new(&self.cfg)?);
            }
            Ok(())
        })();
        if let Err(e) = outcome {
            self.error = e.to_string();
            let _ = self.cleanup();
            let _ = self.session.fail();
            return Err(e);
        }
        self.session.prepared().map_err(|_| err("prepare failed"))?;
        if let Some(o) = owner {
            self.lease = Some((
                o.into(),
                Instant::now() + Duration::from_secs((self.cfg.timeout as u64 * 8).max(30)),
            ));
        }
        self.last_heartbeat = Instant::now();
        Ok(())
    }
    fn start(&mut self, which: &str, owner: Option<&str>) -> io::Result<()> {
        if which != "recording" && which != "twitch" {
            return Err(err("explicit recording/twitch output required"));
        }
        self.guard_lease(owner)?;
        if self.session.state() == Lifecycle::Running {
            return if self.session.output().map(Output::as_str) == Some(which) {
                Ok(())
            } else {
                Err(err("stop before changing outputs"))
            };
        }
        if self.session.state() == Lifecycle::Idle {
            self.prepare(owner)?;
        }
        if self.session.state() != Lifecycle::Ready {
            return Err(err("not prepared"));
        }
        let outcome = (|| -> io::Result<()> {
            if self.cfg.role == "capture" {
                self.spawn("game", media::game(&self.cfg)?)?;
                self.spawn("mic", media::mic(&self.cfg)?)?;
                if self.cfg.camera_enabled && self.cfg.camera_location == "capture" {
                    self.spawn("camera", media::camera(&self.cfg)?)?;
                }
                control::request_peer(
                    &self.cfg,
                    "start",
                    &format!(
                        "{{\"output\":{},\"_owner\":{}}}",
                        config::json_string(which),
                        config::json_string(&self.owner)
                    ),
                )?;
            } else {
                if self.cfg.camera_enabled && self.cfg.camera_location == "production" {
                    self.spawn("camera", media::camera(&self.cfg)?)?;
                }
                self.spawn("rnnoise", media::rnnoise(&self.cfg)?)?;
                let mut monitor = media::ReceiveMonitor::new(self.cfg.camera_enabled);
                self.wait_ready(|| {
                    media::receive_snapshot(&self.cfg)
                        .is_ok_and(|v| monitor.observe(&v, Instant::now()).unwrap_or(false))
                })?;
                self.receive_monitor = Some(monitor);
                let mut o = obs::Obs::connect(&self.cfg)?;
                o.configure(&self.cfg)?;
                o.start(&self.cfg, which)?;
                self.wait_ready(|| {
                    obs::Obs::connect(&self.cfg)
                        .and_then(|mut o| o.status(which))
                        .unwrap_or(false)
                })?;
                self.output_observation = Some(obs::Obs::connect(&self.cfg)?.observe(which)?);
            }
            Ok(())
        })();
        if let Err(e) = outcome {
            self.error = e.to_string();
            let _ = self.cleanup();
            let _ = self.session.fail();
            return Err(e);
        }
        let target = if which == "recording" {
            Output::Recording
        } else {
            Output::Twitch
        };
        self.session
            .start(target)
            .map_err(|_| err("start lifecycle error"))?;
        self.last_health = Instant::now();
        if let Some(o) = owner {
            self.renew_lease(o)?;
        }
        Ok(())
    }
    fn cleanup(&mut self) -> io::Result<()> {
        self.speech.take();
        self.receive_monitor = None;
        self.output_observation = None;
        if self.cfg.role == "production" && self.children.contains_key("obs") {
            if let Ok(mut o) = obs::Obs::connect(&self.cfg) {
                let _ = o.stop();
            }
        }
        if self.cfg.role == "capture"
            && self.children.contains_key("ssh")
            && control::request_peer(
                &self.cfg,
                "stop",
                &format!("{{\"_owner\":{}}}", config::json_string(&self.owner)),
            )
            .is_err()
        {
            self.warn("remote stop unconfirmed; the production ownership lease must expire");
        }
        let mut failed = false;
        for name in ["game", "mic", "camera", "rnnoise", "obs", "mediamtx", "ssh"] {
            if let Some(ch) = self.children.get_mut(name) {
                if ch.stop(Duration::from_millis(200)).is_ok() {
                    self.children.remove(name);
                } else {
                    failed = true;
                }
            }
        }
        if let Some(id) = self.owned_module {
            if media::release_processed_sink(id).is_ok() {
                self.owned_module = None;
            } else {
                failed = true;
            }
        }
        if failed {
            Err(err("owned resources could not all be released; stop again and inspect the enclosing service cgroup"))
        } else {
            Ok(())
        }
    }
    fn stop(&mut self, owner: Option<&str>) -> io::Result<()> {
        if owner.is_some() {
            self.guard_lease(owner)?;
        }
        if self.session.state() == Lifecycle::Idle {
            return Ok(());
        }
        self.session
            .stop()
            .map_err(|_| err("stop lifecycle error"))?;
        if let Err(error) = self.cleanup() {
            self.error = error.to_string();
            return Err(error);
        }
        self.session
            .stopped()
            .map_err(|_| err("stop completion error"))?;
        self.error.clear();
        self.lease = None;
        self.mic_muted = false;
        Ok(())
    }
    fn tick(&mut self) {
        self.expire_lease();
        if let Some(speech) = &mut self.speech {
            speech.tick();
        }
        if matches!(self.session.state(), Lifecycle::Ready | Lifecycle::Running) {
            if self.cfg.role == "capture"
                && self.children.contains_key("ssh")
                && self.last_heartbeat.elapsed() >= Duration::from_secs(2)
            {
                self.last_heartbeat = Instant::now();
                let body = format!("{{\"_owner\":{}}}", config::json_string(&self.owner));
                if control::request_peer(&self.cfg, "heartbeat", &body).is_err() {
                    self.error = "production heartbeat failed; owned capture stopped".into();
                    let _ = self.cleanup();
                    let _ = self.session.fail();
                    return;
                }
            }
            let mut dead = false;
            for child in self.children.values_mut() {
                if !matches!(child.try_wait(), Ok(None)) {
                    dead = true;
                }
            }
            if dead {
                self.error =
                    "owned infrastructure or media process exited; explicit prepare required"
                        .into();
                let _ = self.cleanup();
                let _ = self.session.fail();
            }
            if self.cfg.role == "production"
                && self.session.state() == Lifecycle::Running
                && self.last_health.elapsed() >= Duration::from_secs(1)
            {
                self.last_health = Instant::now();
                let health = (|| -> io::Result<bool> {
                    let snapshot = media::receive_snapshot(&self.cfg)?;
                    if !self
                        .receive_monitor
                        .as_mut()
                        .ok_or_else(|| err("receive monitor unavailable"))?
                        .observe(&snapshot, Instant::now())?
                    {
                        return Ok(false);
                    }
                    let output = self
                        .session
                        .output()
                        .ok_or_else(|| err("output unavailable"))?;
                    let current = obs::Obs::connect(&self.cfg)?.observe(output.as_str())?;
                    let progressing = self.output_observation.as_ref().is_some_and(|previous| {
                        current.active
                            && current
                                .bytes
                                .zip(previous.bytes)
                                .is_some_and(|(now, old)| now > old)
                            && current
                                .frames
                                .zip(previous.frames)
                                .is_none_or(|(now, old)| now > old)
                    });
                    self.output_observation = Some(current);
                    Ok(progressing)
                })();
                if !matches!(health, Ok(true)) {
                    self.error="incoming media or OBS output stopped progressing; output stopped without automatic publication".into();
                    let _ = self.cleanup();
                    let _ = self.session.fail();
                }
            }
        }
    }
    fn expire_lease(&mut self) {
        let expired = self
            .lease
            .as_ref()
            .map(|(_, when)| Instant::now() > *when)
            .unwrap_or(false);
        if expired {
            if self.stop(None).is_ok() {
                self.warn("production owner lease expired; owned media stopped");
            } else {
                self.warn("production owner lease expired; cleanup is incomplete");
            }
        }
    }
    fn warn(&mut self, message: &str) {
        if self.warnings.len() == 16 {
            self.warnings.remove(0);
        }
        self.warnings.push(message.into());
    }
    fn command(&mut self, cmd: &str, args: &str) -> io::Result<String> {
        self.expire_lease();
        let args: Value = serde_json::from_str(args).map_err(|_| err("invalid command JSON"))?;
        let invocation = Invocation::parse(cmd, &args, self.cfg.tts_max_text as usize)?;
        self.execute(invocation)
    }
    fn execute(&mut self, invocation: Invocation) -> io::Result<String> {
        let owner = invocation.owner.as_deref();
        if owner.is_some() && self.cfg.role != "production" {
            return Err(err("only production accepts remote ownership"));
        }
        if let Some(o) = owner {
            if let Some((held, _)) = &self.lease {
                if held != o {
                    return Err(err("session belongs to another production owner"));
                }
            }
        }
        match invocation.command {
            Command::Status=>Ok(self.status()),
            Command::Heartbeat=>{self.renew_lease(owner.ok_or_else(||err("production owner required"))?)?;Ok(self.status())},
            Command::Doctor=>doctor(&self.cfg),
            Command::Prepare=>{self.prepare(owner)?;Ok(self.status())},
            Command::Start(output)=>{self.start(output.as_str(),owner)?;Ok(self.status())},
            Command::Stop=>{self.stop(owner)?;Ok(self.status())},
            Command::Diagnostics=>Ok(json!({"version":1,"role":self.cfg.role,"state":json_state(self.session.state()),"output":self.session.output().map(Output::as_str),"children":self.children.keys().collect::<Vec<_>>(),"mic_muted":self.mic_muted,"retries":0}).to_string()),
            Command::Routes{settings}=>self.routes(settings.as_ref()),
            Command::Devices{remote}=>self.devices(remote),
            command=>{
                if !matches!(self.session.state(),Lifecycle::Ready|Lifecycle::Running|Lifecycle::Degraded){return Err(err("prepare the session first"));}
                if self.cfg.role=="capture"{return self.peer_command(&command);}
                if !self.children.contains_key("obs"){return Err(err("no owned OBS session"));}
                match command {
                    Command::Mic(action)=>{
                        let mut obs=obs::Obs::connect(&self.cfg)?;
                        if action!=MicAction::Status {
                            let muted=action==MicAction::Mute;
                            obs.call("SetInputMute",&json!({"inputName":"MicProcessed","inputMuted":muted}).to_string())?;self.mic_muted=muted;
                        }
                        let ret:Value=serde_json::from_str(&obs.call("GetInputMute","{\"inputName\":\"MicProcessed\"}")?).map_err(|_|err("invalid OBS mute response"))?;
                        let muted=ret["d"]["responseData"]["inputMuted"].as_bool().ok_or_else(||err("invalid OBS mute response"))?;
                        self.mic_muted=muted;Ok(json!({"muted":muted}).to_string())
                    },
                    Command::Overlay{text}=>{obs::Obs::connect(&self.cfg)?.overlay(&text)?;Ok(json!({"updated":true}).to_string())},
                    Command::Preview=>obs::Obs::connect(&self.cfg)?.preview(),
                    Command::Tts(action)=>{let (_,args)=Command::Tts(action).request();self.speech.as_mut().ok_or_else(||err("speech queue unavailable"))?.command(args["action"].as_str().unwrap(),&[]).map(|v|v.to_string())},
                    Command::Say{text,id}=>{let id=id.unwrap_or(rand_hex()?);self.speech.as_mut().ok_or_else(||err("speech queue unavailable"))?.enqueue(&text,&id).map(|v|v.to_string())},
                    Command::TtsNext=>Ok(json!({"job":self.speech.as_mut().ok_or_else(||err("speech queue unavailable"))?.next_ready()}).to_string()),
                    Command::TtsAck{id}=>Ok(self.speech.as_mut().ok_or_else(||err("speech queue unavailable"))?.ack(&id).to_string()),
                    Command::TtsFinished{id}=>Ok(self.speech.as_mut().ok_or_else(||err("speech queue unavailable"))?.finished(&id).to_string()),
                    _=>Err(err("command is not a prepared-session control"))
                }
            }
        }
    }
    fn peer_command(&self, command: &Command) -> io::Result<String> {
        let (name, mut args) = command.request();
        args["_owner"] = json!(self.owner);
        control::request_peer(&self.cfg, name, &args.to_string())
    }
    fn routes(&mut self, settings: Option<&Value>) -> io::Result<String> {
        if let Some(patch) = settings {
            if self.session.state() != Lifecycle::Idle {
                return Err(err("stop before changing routes"));
            }
            let mut cfg = apply_settings(&self.cfg, patch)?;
            let shared: serde_json::Map<String, Value> = patch
                .as_object()
                .unwrap()
                .iter()
                .filter(|(k, _)| matches!(k.as_str(), "camera" | "tts"))
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect();
            if self.cfg.role == "capture" && !shared.is_empty() {
                return Err(err("shared remote selections require a prepared compatible peer; no partial settings were saved"));
            }
            let saved = self.cfg.state_dir.join("settings.json");
            let mut previous: Value = if saved.exists() {
                serde_json::from_str(&config::secret(&saved, 65536)?)
                    .map_err(|_| err("invalid saved selections"))?
            } else {
                json!({})
            };
            merge_settings(&mut previous, patch)?;
            crate::state::atomic_file(&saved, &previous.to_string())?;
            cfg.state_dir = self.cfg.state_dir.clone();
            self.cfg = cfg;
        }
        let doc: Value = serde_json::from_str(&self.cfg.document)
            .map_err(|_| err("invalid normalized configuration"))?;
        Ok(json!({"routes":doc["routes"],"transport":transport(&self.cfg),"selection":{"peer":{"ssh_host":self.cfg.ssh_host},"capture":{"target":self.cfg.target,"game_audio":self.cfg.game_audio},"audio":{"mic_source":self.cfg.mic_source,"tts_sink":self.cfg.tts_sink,"mic_offset_ms":self.cfg.mic_offset},"camera":doc["camera"],"tts":{"enabled":self.cfg.tts_enabled,"mix_remote":self.cfg.tts_mix_remote,"eventsub":self.cfg.eventsub_enabled}}}).to_string())
    }
    fn devices(&mut self, remote: bool) -> io::Result<String> {
        let local = media::devices(&self.cfg.role)?;
        let mut result = json!({"local":local});
        if remote && self.cfg.role == "capture" {
            let temporary = !self.children.contains_key("ssh");
            if temporary {
                self.spawn("ssh", media::tunnel(&self.cfg))?;
            }
            let response = control::request_peer(&self.cfg, "devices", "{\"remote\":false}");
            if temporary {
                if let Some(mut child) = self.children.remove("ssh") {
                    child.stop(Duration::from_millis(100))?;
                }
            }
            let remote: Value =
                serde_json::from_str(&response?).map_err(|_| err("invalid remote discovery"))?;
            result["remote"] = remote["local"].clone();
        }
        Ok(result.to_string())
    }
}
impl Drop for Agent {
    fn drop(&mut self) {
        let _ = self.cleanup();
    }
}
pub fn serve(cfg: config::Config) -> io::Result<()> {
    let token = cfg.token(false)?;
    let listener = control::listener(&cfg)?;
    let mut agent = Agent::new(cfg.clone())?;
    let directory = std::env::var_os("SPLITCAST_WEB_ASSETS").map(std::path::PathBuf::from);
    let assets = Arc::new(crate::web::Assets::load(directory.as_deref())?);
    for sig in [2, 15] {
        if unsafe { signal(sig, shutdown) } == usize::MAX {
            return Err(io::Error::last_os_error());
        }
    }
    let (requests, pending) =
        mpsc::sync_channel::<(control::Request, mpsc::SyncSender<(u16, String)>)>(8);
    let connections = Arc::new(AtomicUsize::new(0));
    eprintln!(
        "SplitCast Rust candidate: loopback control on 127.0.0.1:{}; no automatic streaming",
        cfg.control_port
    );
    while !SHUTDOWN.load(Ordering::Relaxed) {
        agent.tick();
        match listener.accept() {
            Ok((mut stream, _)) => {
                if connections.load(Ordering::Relaxed) >= 8 {
                    drop(stream);
                    continue;
                }
                connections.fetch_add(1, Ordering::Relaxed);
                let connections = Arc::clone(&connections);
                let requests = requests.clone();
                let token = token.clone();
                let port = cfg.control_port;
                let assets = Arc::clone(&assets);
                thread::spawn(move || {
                    struct Slot(Arc<AtomicUsize>);
                    impl Drop for Slot {
                        fn drop(&mut self) {
                            self.0.fetch_sub(1, Ordering::Relaxed);
                        }
                    }
                    let _slot = Slot(connections);
                    let request = match control::recv(&mut stream, port, &token) {
                        Ok(r) => r,
                        Err(_) => {
                            let _ = control::reply(
                                &mut stream,
                                403,
                                "{\"error\":\"unauthorized or malformed request\"}",
                            );
                            return;
                        }
                    };
                    if request.method == "GET" {
                        if let Some((mime, body)) = assets.get(&request.path) {
                            let _ = control::reply_bytes(&mut stream, 200, mime, body);
                            return;
                        }
                        if request.path == "/" {
                            let _=control::reply(&mut stream,503,"{\"error\":\"Rust WASM assets unavailable; use the TUI or build the web package\"}");
                            return;
                        }
                    }
                    let (answer, receive) = mpsc::sync_channel(1);
                    if requests.try_send((request, answer)).is_err() {
                        let _ =
                            control::reply(&mut stream, 503, "{\"error\":\"command queue full\"}");
                        return;
                    }
                    let (code, body) = receive
                        .recv_timeout(Duration::from_secs(180))
                        .unwrap_or((503, "{\"error\":\"agent unavailable\"}".into()));
                    let _ = control::reply(&mut stream, code, &body);
                });
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(e) => return Err(e),
        }
        if let Ok((request, answer)) = pending.try_recv() {
            let result = if request.method == "GET" && request.path == "/api/status" {
                agent.command("status", "{}").map(|s| (200, s))
            } else if request.method == "POST" && request.path == "/api/command" {
                (|| {
                    let invocation =
                        Invocation::from_body(&request.body, agent.cfg.tts_max_text as usize)?;
                    agent.expire_lease();
                    agent.execute(invocation).map(|s| (200, s))
                })()
            } else {
                Ok((404, "{\"error\":\"unknown endpoint\"}".into()))
            };
            let response = result.unwrap_or_else(|e| {
                (
                    409,
                    format!("{{\"error\":{}}}", config::json_string(&e.to_string())),
                )
            });
            let _ = answer.send(response);
        }
        thread::sleep(Duration::from_millis(20));
    }
    agent.stop(None)
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn prepared_agent() -> Agent {
        let cfg = config::Config::load(Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/agent-example.json"
        )))
        .unwrap();
        let mut cfg = cfg;
        cfg.role = "production".into();
        cfg.state_dir = std::env::temp_dir().join(format!(
            "splitcast-agent-test-{}-{}",
            std::process::id(),
            rand_hex().unwrap()
        ));
        let mut agent = Agent::new(cfg).unwrap();
        agent.session.prepare().unwrap();
        agent.session.prepared().unwrap();
        agent
    }

    #[test]
    fn heartbeat_cannot_claim_a_locally_prepared_session() {
        let mut agent = prepared_agent();
        assert!(
            agent
                .command("heartbeat", "{\"_owner\":\"intruder\"}")
                .is_err(),
            "heartbeat claimed a locally owned session"
        );
    }

    #[test]
    fn matching_remote_owner_renews_without_starting_an_output() {
        let mut agent = prepared_agent();
        let deadline = Instant::now() + Duration::from_secs(1);
        agent.lease = Some(("session_123".into(), deadline));
        agent
            .command("heartbeat", "{\"_owner\":\"session_123\"}")
            .unwrap();
        assert!(agent.lease.as_ref().unwrap().1 > deadline);
        assert_eq!(agent.session.state(), Lifecycle::Ready);
        assert_eq!(agent.session.output(), None);
    }

    #[test]
    fn expired_owner_cannot_revive_its_lease() {
        let mut agent = prepared_agent();
        agent.lease = Some(("expired".into(), Instant::now() - Duration::from_secs(1)));
        assert!(
            agent
                .command("heartbeat", "{\"_owner\":\"expired\"}")
                .is_err(),
            "expired owner revived its lease"
        );
        assert_eq!(agent.session.state(), Lifecycle::Idle);
    }

    #[test]
    fn local_operator_can_emergency_stop_a_remote_session() {
        let mut agent = prepared_agent();
        agent.lease = Some(("remote".into(), Instant::now() + Duration::from_secs(30)));
        assert!(
            agent.command("stop", "{}").is_ok(),
            "local emergency stop was refused"
        );
        assert_eq!(agent.session.state(), Lifecycle::Idle);
    }

    #[test]
    fn repeated_start_is_idempotent_without_switching_to_twitch() {
        let mut agent = prepared_agent();
        agent.session.start(Output::Recording).unwrap();
        assert!(
            agent.start("recording", None).is_ok(),
            "repeated recording start was refused"
        );
        assert!(agent.start("twitch", None).is_err());
        assert_eq!(agent.session.output(), Some(Output::Recording));
    }

    #[test]
    fn command_rejects_unknown_arguments_and_non_string_owners() {
        let mut agent = prepared_agent();
        for (cmd, args) in [
            ("status", "{\"unexpected\":true}"),
            ("status", "{\"_owner\":[]}"),
            ("status", "null"),
            ("status", "{} {}"),
            ("start", "{\"output\":false}"),
        ] {
            assert!(agent.command(cmd, args).is_err(), "accepted {cmd} {args}");
        }
    }
}
