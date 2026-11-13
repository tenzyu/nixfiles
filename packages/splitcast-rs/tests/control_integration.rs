#![cfg(unix)]

use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

const BIN: &str = env!("CARGO_BIN_EXE_splitcast-rs-core");
const TOKEN: &str = "integration-private-token-never-serialize";
const LIMIT: Duration = Duration::from_secs(5);
static NEXT: AtomicUsize = AtomicUsize::new(0);
static NETWORK: Mutex<()> = Mutex::new(());

struct Fixture {
    _network: Option<MutexGuard<'static, ()>>,
    root: PathBuf,
    config: PathBuf,
    port: u16,
}

impl Fixture {
    fn new() -> Self {
        let network = NETWORK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let base = if Path::new("/tmp/opencode").is_dir() {
            PathBuf::from("/tmp/opencode")
        } else {
            std::env::temp_dir()
        };
        let root = base.join(format!(
            "splitcast-control-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
        let token = root.join("control.token");
        fs::write(&token, TOKEN).unwrap();
        fs::set_permissions(&token, fs::Permissions::from_mode(0o600)).unwrap();
        let mut cfg: Value = serde_json::from_str(include_str!("agent-example.json")).unwrap();
        let reservations: Vec<_> = (0..9)
            .map(|_| TcpListener::bind("127.0.0.1:0").unwrap())
            .collect();
        let ports: Vec<_> = reservations
            .iter()
            .map(|l| l.local_addr().unwrap().port())
            .collect();
        cfg["peer"]["control_port"] = json!(ports[0]);
        cfg["peer"]["remote_control_port"] = json!(ports[1]);
        cfg["peer"]["forward_control_port"] = json!(ports[2]);
        cfg["peer"]["ssh_port"] = json!(ports[3]);
        cfg["capture"]["rtmp_port"] = json!(ports[4]);
        cfg["capture"]["rtsp_port"] = json!(ports[5]);
        cfg["capture"]["api_port"] = json!(ports[6]);
        cfg["obs"]["websocket_port"] = json!(ports[7]);
        cfg["tts"]["voicevox_url"] = json!(format!("http://127.0.0.1:{}", ports[8]));
        cfg["peer"]["token_file"] = json!(token);
        cfg["peer"]["remote_token_file"] = json!(root.join("remote.token"));
        cfg["peer"]["state_dir"] = json!(root.join("state"));
        cfg["obs"]["password_file"] = json!(root.join("obs.password"));
        cfg["obs"]["twitch_key_file"] = json!(root.join("twitch.key"));
        cfg["tts"]["credentials_file"] = json!(root.join("twitch.json"));
        cfg["obs"]["recording_dir"] = json!(root.join("recordings"));
        let config = root.join("config.json");
        fs::write(&config, cfg.to_string()).unwrap();
        Self {
            _network: Some(network),
            root,
            config,
            port: ports[0],
        }
    }

    fn spawn(&self, args: &[&str], input: &[u8], assets: Option<&Path>) -> Process {
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        let out = self.root.join(format!("stdout-{id}"));
        let err = self.root.join(format!("stderr-{id}"));
        let mut command = Command::new(BIN);
        command
            .arg("--config")
            .arg(&self.config)
            .args(args)
            .env_remove("SPLITCAST_WEB_ASSETS")
            .stdin(Stdio::piped())
            .stdout(File::create(&out).unwrap())
            .stderr(File::create(&err).unwrap());
        if let Some(assets) = assets {
            command.env("SPLITCAST_WEB_ASSETS", assets);
        }
        if self.root.join("tools").is_dir() {
            command.env("PATH", self.root.join("tools"));
        }
        let child = command.spawn().unwrap();
        let mut process = Process { child, out, err };
        process
            .child
            .stdin
            .take()
            .unwrap()
            .write_all(input)
            .unwrap();
        process
    }

    fn cli(&self, args: &[&str], input: &[u8]) -> (ExitStatus, String, String) {
        let mut child = self.spawn(args, input, None);
        let status = child.wait(LIMIT);
        (status, child.stdout(), child.stderr())
    }

    fn agent(&self, assets: Option<&Path>) -> Process {
        let mut agent = self.spawn(&["agent"], b"", assets);
        let deadline = Instant::now() + LIMIT;
        loop {
            if let Some(status) = agent.child.try_wait().unwrap() {
                panic!("agent exited {status}: {}", agent.stderr());
            }
            if TcpStream::connect(("127.0.0.1", self.port)).is_ok() {
                return agent;
            }
            assert!(
                Instant::now() < deadline,
                "agent did not listen: {}",
                agent.stderr()
            );
            thread::sleep(Duration::from_millis(10));
        }
    }

    fn headers(&self) -> String {
        format!("Host: 127.0.0.1:{}\r\nOrigin: http://127.0.0.1:{}\r\nAuthorization: Bearer {TOKEN}\r\n", self.port, self.port)
    }

    fn exchange(&self, request: &[u8]) -> Response {
        let mut stream = TcpStream::connect(("127.0.0.1", self.port)).unwrap();
        stream.set_read_timeout(Some(LIMIT)).unwrap();
        stream.set_write_timeout(Some(LIMIT)).unwrap();
        stream.write_all(request).unwrap();
        stream.shutdown(Shutdown::Write).unwrap();
        let mut bytes = Vec::new();
        while !bytes.ends_with(b"\r\n\r\n") {
            let mut byte = [0];
            stream.read_exact(&mut byte).unwrap();
            bytes.push(byte[0]);
            assert!(bytes.len() < 20 * 1024, "bounded HTTP response headers");
        }
        let header = std::str::from_utf8(&bytes).unwrap();
        let length: usize = header
            .lines()
            .find_map(|l| l.strip_prefix("Content-Length: "))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(length <= 4 * 1024 * 1024, "bounded HTTP response body");
        let offset = bytes.len();
        bytes.resize(offset + length, 0);
        stream.read_exact(&mut bytes[offset..]).unwrap();
        Response::parse(bytes)
    }

    fn get(&self, path: &str) -> Response {
        self.exchange(format!("GET {path} HTTP/1.1\r\n{}\r\n", self.headers()).as_bytes())
    }

    fn post(&self, body: &[u8]) -> Response {
        let mut request = format!("POST /api/command HTTP/1.1\r\n{}Content-Type: application/json\r\nContent-Length: {}\r\n\r\n", self.headers(), body.len()).into_bytes();
        request.extend_from_slice(body);
        self.exchange(&request)
    }

    fn command(&self, command: &str, args: Value) -> Response {
        self.post(
            json!({"command":command,"args":args})
                .to_string()
                .as_bytes(),
        )
    }

    fn config(&self) -> Value {
        serde_json::from_slice(&fs::read(&self.config).unwrap()).unwrap()
    }

    fn save_config(&self, cfg: &Value) {
        fs::write(&self.config, cfg.to_string()).unwrap();
    }

    fn stub_workers(&self) {
        let tools = self.root.join("tools");
        fs::create_dir(&tools).unwrap();
        let shell = executable("sh");
        let sleep = executable("sleep");
        for name in ["ffmpeg", "ffprobe", "pactl", "ssh", "gpu-screen-recorder"] {
            let path = tools.join(name);
            fs::write(
                &path,
                format!(
                    "#!{}\nprintf '%s\\n' \"$$\" > \"$0.pid\"\nexec '{}' 60\n",
                    shell.display(),
                    sleep.to_str().unwrap().replace('\'', "'\\''")
                ),
            )
            .unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        }
        fs::write(self.root.join("remote.token"), TOKEN).unwrap();
        fs::set_permissions(
            self.root.join("remote.token"),
            fs::Permissions::from_mode(0o600),
        )
        .unwrap();
        let mut cfg = self.config();
        cfg["peer"]["timeout_seconds"] = json!(1);
        cfg["capture"]["target"] = json!("authorized-test-window");
        cfg["capture"]["game_audio"] = json!("app:authorized-test-game");
        cfg["audio"]["mic_source"] = json!("alsa_input.integration_microphone");
        self.save_config(&cfg);
    }

    fn worker_pid(&self, name: &str) -> i32 {
        let path = self.root.join("tools").join(format!("{name}.pid"));
        let deadline = Instant::now() + LIMIT;
        loop {
            if let Ok(text) = fs::read_to_string(&path) {
                if let Ok(pid) = text.trim().parse() {
                    return pid;
                }
            }
            assert!(
                Instant::now() < deadline,
                "stub worker never launched: {name}"
            );
            thread::sleep(Duration::from_millis(10));
        }
    }
}

fn executable(name: &str) -> PathBuf {
    std::env::split_paths(&std::env::var_os("PATH").expect("test runner PATH"))
        .map(|dir| dir.join(name))
        .find(|path| {
            path.is_file()
                && path
                    .metadata()
                    .is_ok_and(|meta| meta.permissions().mode() & 0o111 != 0)
        })
        .map(|path| {
            if path.is_absolute() {
                path
            } else {
                std::env::current_dir().unwrap().join(path)
            }
        })
        .unwrap_or_else(|| panic!("test harness requires {name} on PATH"))
}

#[derive(Clone, Copy)]
enum PeerBehavior {
    Compatible,
    Incompatible,
    MismatchedCamera { omit_transport: bool },
    RejectPrepare,
    LosePrepareResponse,
    RefuseFirstStop,
}

struct Peer {
    requests: Arc<Mutex<Vec<Value>>>,
    shutdown: Arc<AtomicBool>,
    thread: Option<thread::JoinHandle<()>>,
}

impl Peer {
    fn new(fixture: &Fixture, behavior: PeerBehavior) -> Self {
        let cfg = fixture.config();
        let port = cfg["peer"]["forward_control_port"].as_u64().unwrap() as u16;
        let host_port = cfg["peer"]["remote_control_port"].as_u64().unwrap() as u16;
        let listener = TcpListener::bind(("127.0.0.1", port)).unwrap();
        listener.set_nonblocking(true).unwrap();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let shutdown = Arc::new(AtomicBool::new(false));
        let seen = Arc::clone(&requests);
        let stop = Arc::clone(&shutdown);
        let thread = thread::spawn(move || {
            let mut muted = false;
            let mut stop_requests = 0;
            while !stop.load(Ordering::Relaxed) {
                let mut stream = match listener.accept() {
                    Ok((stream, _)) => stream,
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(5));
                        continue;
                    }
                    Err(e) => panic!("fake peer accept: {e}"),
                };
                let request = splitcast_rs_core::control::recv(&mut stream, host_port, TOKEN)
                    .expect("authenticated loopback peer request");
                let request: Value = serde_json::from_str(&request.body).unwrap();
                seen.lock().unwrap().push(request.clone());
                if request["command"] == "prepare"
                    && matches!(behavior, PeerBehavior::LosePrepareResponse)
                {
                    continue;
                }
                let mut status = 200;
                let response = match request["command"].as_str().unwrap() {
                    "status" => {
                        let mut hello = json!({"version":1,"role":"production","engine":"rust-candidate","state":"idle"});
                        if matches!(behavior, PeerBehavior::Incompatible) {
                            hello.as_object_mut().unwrap().remove("engine");
                        }
                        hello
                    }
                    "routes" => {
                        let mut camera = cfg["camera"].clone();
                        let mut transport = json!({
                            "version":1,
                            "video":{"codec":"H264","width":cfg["capture"]["width"],"height":cfg["capture"]["height"],"fps":cfg["capture"]["fps"]},
                            "audio":{"game":"MPEG-4 Audio","mic":"Opus","rate":48000},
                            "ports":{"rtmp":cfg["capture"]["rtmp_port"],"rtsp":cfg["capture"]["rtsp_port"]},
                            "camera":camera
                        });
                        if let PeerBehavior::MismatchedCamera { omit_transport } = behavior {
                            camera["location"] = json!("production");
                            camera["device"] = json!("/dev/v4l/by-id/other-test-camera");
                            transport["camera"] = camera.clone();
                            if omit_transport {
                                transport.as_object_mut().unwrap().remove("camera");
                            }
                        }
                        json!({"transport":transport,"routes":cfg["routes"],"selection":{"camera":camera}})
                    }
                    "prepare" if matches!(behavior, PeerBehavior::RejectPrepare) => {
                        status = 409;
                        json!({"error":"injected prepare refusal"})
                    }
                    "mic" => {
                        match request["args"]["action"].as_str().unwrap() {
                            "mute" => muted = true,
                            "unmute" => muted = false,
                            "status" => (),
                            action => panic!("unexpected mic action: {action}"),
                        }
                        json!({"muted":muted})
                    }
                    "stop" if matches!(behavior, PeerBehavior::RefuseFirstStop) && stop_requests == 0 => {
                        stop_requests += 1;
                        status = 409;
                        json!({"error":"injected unconfirmed stop"})
                    }
                    "prepare" | "start" | "stop" | "heartbeat" => {
                        json!({"version":1,"role":"production","engine":"rust-candidate","state":"ready"})
                    }
                    command => panic!("unexpected peer command: {command}"),
                }
                .to_string();
                write!(stream, "HTTP/1.1 {status} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{response}", if status == 200 { "OK" } else { "Conflict" }, response.len()).unwrap();
            }
        });
        Self {
            requests,
            shutdown,
            thread: Some(thread),
        }
    }

    fn requests(&self) -> Vec<Value> {
        self.requests.lock().unwrap().clone()
    }
}

impl Drop for Peer {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        let result = self.thread.take().unwrap().join();
        if !thread::panicking() {
            result.expect("fake peer failed");
        }
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

struct Process {
    child: Child,
    out: PathBuf,
    err: PathBuf,
}

impl Process {
    fn wait(&mut self, timeout: Duration) -> ExitStatus {
        let deadline = Instant::now() + timeout;
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                return status;
            }
            assert!(
                Instant::now() < deadline,
                "child did not exit: {}",
                self.stderr()
            );
            thread::sleep(Duration::from_millis(10));
        }
    }

    fn stdout(&self) -> String {
        fs::read_to_string(&self.out).unwrap()
    }

    fn stderr(&self) -> String {
        fs::read_to_string(&self.err).unwrap()
    }

    fn terminate(&mut self) {
        unsafe extern "C" {
            fn kill(pid: i32, signal: i32) -> i32;
        }
        assert_eq!(unsafe { kill(self.child.id() as i32, 15) }, 0);
        assert!(
            self.wait(Duration::from_secs(2)).success(),
            "{}",
            self.stderr()
        );
    }
}

impl Drop for Process {
    fn drop(&mut self) {
        if !matches!(self.child.try_wait(), Ok(Some(_))) {
            unsafe { libc::kill(self.child.id() as i32, libc::SIGTERM) };
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline {
                if matches!(self.child.try_wait(), Ok(Some(_))) {
                    return;
                }
                thread::sleep(Duration::from_millis(10));
            }
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

struct Response {
    code: u16,
    head: String,
    body: Vec<u8>,
}

impl Response {
    fn parse(bytes: Vec<u8>) -> Self {
        let end = bytes
            .windows(4)
            .position(|b| b == b"\r\n\r\n")
            .expect("HTTP response headers");
        let head = String::from_utf8(bytes[..end].to_vec()).unwrap();
        let code = head.split_whitespace().nth(1).unwrap().parse().unwrap();
        let body = bytes[end + 4..].to_vec();
        let length: usize = head
            .lines()
            .find_map(|l| l.strip_prefix("Content-Length: "))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert_eq!(body.len(), length, "finite response body");
        Self { code, head, body }
    }

    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap()
    }

    fn no_secret(&self) {
        assert!(!String::from_utf8_lossy(&self.body).contains(TOKEN));
        assert!(!self.head.contains(TOKEN));
    }
}

fn assert_idle(status: &Value) {
    assert_eq!(status["state"], "idle");
    assert_eq!(status["output"], Value::Null);
    assert_eq!(status["children"], json!([]));
}

fn assert_failed_without_workers(fixture: &Fixture) {
    let status = fixture.get("/api/status").json();
    assert_eq!(status["state"], "failed", "{status}");
    assert_eq!(status["output"], Value::Null, "{status}");
    assert_eq!(status["children"], json!([]), "{status}");
    let pid = fixture.worker_pid("ssh");
    assert_eq!(
        unsafe { libc::kill(pid, 0) },
        -1,
        "owned tunnel {pid} survived cleanup"
    );
    assert_eq!(
        std::io::Error::last_os_error().raw_os_error(),
        Some(libc::ESRCH)
    );
}

#[test]
fn native_validation_rejects_monitor_microphone_sources() {
    let mut fixture = Fixture::new();
    let mut cfg = fixture.config();
    let mut accepted = Vec::new();
    for source in [
        "alsa_output.integration_stereo.monitor",
        "splitcast_mic.monitor",
    ] {
        cfg["audio"]["mic_source"] = json!(source);
        for extension in ["json", "toml"] {
            fixture.config = fixture.root.join(format!("config.{extension}"));
            let document = if extension == "toml" {
                toml::to_string(&serde_json::from_value::<toml::Value>(cfg.clone()).unwrap())
                    .unwrap()
            } else {
                cfg.to_string()
            };
            fs::write(&fixture.config, document).unwrap();
            let (status, out, err) = fixture.cli(&["validate"], b"");
            if status.success() {
                accepted.push(format!("{extension} accepted {source}: {out} {err}"));
            }
        }
    }
    assert!(
        accepted.is_empty(),
        "validate accepted monitor microphones: {accepted:?}"
    );
}

#[test]
fn native_validation_keeps_raw_and_unselected_microphones_valid() {
    let fixture = Fixture::new();
    let mut cfg = fixture.config();
    for source in ["", "alsa_input.integration_microphone"] {
        cfg["audio"]["mic_source"] = json!(source);
        fixture.save_config(&cfg);
        let (status, out, err) = fixture.cli(&["validate"], b"");
        assert!(status.success(), "{source:?}: {err}");
        assert_eq!(serde_json::from_str::<Value>(&out).unwrap()["valid"], true);
    }
}

#[test]
fn real_agent_routes_reject_monitor_microphones_without_saving() {
    let fixture = Fixture::new();
    let _agent = fixture.agent(None);
    let before = fixture.command("routes", json!({})).json();
    for source in [
        "alsa_output.integration_stereo.monitor",
        "splitcast_mic.monitor",
    ] {
        let response = fixture.command(
            "routes",
            json!({"settings":{"audio":{"mic_source":source}}}),
        );
        assert_eq!(
            response.code,
            409,
            "monitor microphone was accepted: {}",
            response.json()
        );
        assert_eq!(fixture.command("routes", json!({})).json(), before);
        assert!(!fixture.root.join("state/capture/settings.json").exists());
        assert_idle(&fixture.get("/api/status").json());
    }
}

#[test]
fn real_agent_routes_accept_raw_microphone_selection() {
    let fixture = Fixture::new();
    let mut agent = fixture.agent(None);
    let source = "alsa_input.integration_microphone";
    let response = fixture.command(
        "routes",
        json!({"settings":{"audio":{"mic_source":source}}}),
    );
    assert_eq!(response.code, 200, "{}", response.json());
    assert_eq!(response.json()["selection"]["audio"]["mic_source"], source);
    assert_idle(&fixture.get("/api/status").json());
    agent.terminate();
    let _restarted = fixture.agent(None);
    assert_eq!(
        fixture.command("routes", json!({})).json()["selection"]["audio"]["mic_source"],
        source
    );
}

#[test]
fn real_agent_refuses_mismatched_camera_before_remote_prepare() {
    for omit_transport in [true, false] {
        let fixture = Fixture::new();
        fixture.stub_workers();
        let mut cfg = fixture.config();
        cfg["camera"]["enabled"] = json!(true);
        cfg["camera"]["device"] = json!("/dev/v4l/by-id/integration-nonexistent-camera");
        for route in cfg["routes"].as_array_mut().unwrap() {
            if route["id"] == "camera" {
                route["enabled"] = json!(true);
            }
        }
        fixture.save_config(&cfg);
        let peer = Peer::new(&fixture, PeerBehavior::MismatchedCamera { omit_transport });
        let _agent = fixture.agent(None);
        let response = fixture.command("prepare", json!({}));
        assert_eq!(
            response.code,
            409,
            "mismatched camera reached ready: {}",
            response.json()
        );
        assert_failed_without_workers(&fixture);
        assert!(peer
            .requests()
            .iter()
            .all(|request| !matches!(request["command"].as_str(), Some("prepare" | "start"))));
        assert_eq!(
            fixture.command("routes", json!({})).json()["transport"]["camera"],
            cfg["camera"],
            "transport must publish the full camera contract"
        );
    }
}

#[test]
fn real_agent_does_not_send_stop_to_an_incompatible_peer() {
    let fixture = Fixture::new();
    fixture.stub_workers();
    let peer = Peer::new(&fixture, PeerBehavior::Incompatible);
    let mut agent = fixture.agent(None);
    let response = fixture.command("prepare", json!({}));
    assert_eq!(response.code, 409, "{}", response.json());
    assert_failed_without_workers(&fixture);
    agent.terminate();
    let requests = peer.requests();
    assert!(!requests.is_empty(), "peer compatibility was never probed");
    assert!(
        requests
            .iter()
            .all(|request| request["command"] == "status"),
        "incompatible peer received a mutating command: {requests:?}"
    );
}

#[test]
fn real_agent_compatible_prepare_and_stop_release_owned_workers() {
    let fixture = Fixture::new();
    fixture.stub_workers();
    let peer = Peer::new(&fixture, PeerBehavior::Compatible);
    let _agent = fixture.agent(None);
    let prepared = fixture.command("prepare", json!({}));
    assert_eq!(
        prepared.code,
        200,
        "compatible full-camera peer was rejected: {}",
        prepared.json()
    );
    assert_eq!(prepared.json()["state"], "ready");
    assert_eq!(prepared.json()["children"], json!(["ssh"]));
    let pid = fixture.worker_pid("ssh");
    let stopped = fixture.command("stop", json!({}));
    assert_eq!(stopped.code, 200, "{}", stopped.json());
    assert_idle(&stopped.json());
    assert_eq!(
        unsafe { libc::kill(pid, 0) },
        -1,
        "owned tunnel survived stop"
    );
    let requests = peer.requests();
    let owner = &requests
        .iter()
        .find(|request| request["command"] == "prepare")
        .unwrap()["args"]["_owner"];
    assert_eq!(owner.as_str().unwrap().len(), 32);
    assert!(owner
        .as_str()
        .unwrap()
        .bytes()
        .all(|byte| byte.is_ascii_hexdigit()));
    let stop = requests
        .iter()
        .find(|request| request["command"] == "stop")
        .unwrap();
    assert_eq!(&stop["args"]["_owner"], owner);
}

#[test]
fn real_agent_failed_remote_prepare_releases_tunnel_and_sends_owned_cleanup() {
    let fixture = Fixture::new();
    fixture.stub_workers();
    let peer = Peer::new(&fixture, PeerBehavior::RejectPrepare);
    let _agent = fixture.agent(None);
    let response = fixture.command("prepare", json!({}));
    assert_eq!(response.code, 409, "{}", response.json());
    assert_failed_without_workers(&fixture);
    let requests = peer.requests();
    let prepare = requests
        .iter()
        .find(|request| request["command"] == "prepare")
        .expect("compatible peer must receive prepare before its injected refusal");
    let stop = requests
        .iter()
        .find(|request| request["command"] == "stop")
        .expect("a peer that received prepare requires owned cleanup");
    assert_eq!(stop["args"]["_owner"], prepare["args"]["_owner"]);
    assert_eq!(fixture.command("stop", json!({})).code, 200);
    assert_idle(&fixture.get("/api/status").json());
}

#[test]
fn real_agent_lost_prepare_response_still_requires_owned_cleanup() {
    let fixture = Fixture::new();
    fixture.stub_workers();
    let peer = Peer::new(&fixture, PeerBehavior::LosePrepareResponse);
    let _agent = fixture.agent(None);
    assert_eq!(fixture.command("prepare", json!({})).code, 409);
    assert_failed_without_workers(&fixture);
    let requests = peer.requests();
    let prepare = requests.iter().find(|r| r["command"] == "prepare").unwrap();
    let stop = requests.iter().find(|r| r["command"] == "stop").unwrap();
    assert_eq!(stop["args"]["_owner"], prepare["args"]["_owner"]);
    assert_eq!(fixture.command("stop", json!({})).code, 200);
    assert_idle(&fixture.get("/api/status").json());
}

#[test]
fn real_agent_unconfirmed_stop_retains_ownership_for_explicit_retry() {
    let fixture = Fixture::new();
    fixture.stub_workers();
    let peer = Peer::new(&fixture, PeerBehavior::RefuseFirstStop);
    let _agent = fixture.agent(None);
    assert_eq!(fixture.command("prepare", json!({})).code, 200);
    let pid = fixture.worker_pid("ssh");
    assert_eq!(fixture.command("stop", json!({})).code, 409);
    let stopping = fixture.get("/api/status").json();
    assert_eq!(stopping["state"], "stopping");
    assert_eq!(stopping["children"], json!([]));
    assert_eq!(unsafe { libc::kill(pid, 0) }, -1);
    assert_eq!(fixture.command("stop", json!({})).code, 200);
    assert_idle(&fixture.get("/api/status").json());
    let requests = peer.requests();
    let owner = &requests.iter().find(|r| r["command"] == "prepare").unwrap()["args"]["_owner"];
    let stops: Vec<_> = requests.iter().filter(|r| r["command"] == "stop").collect();
    assert_eq!(stops.len(), 2);
    assert!(stops.iter().all(|r| &r["args"]["_owner"] == owner));
}

#[test]
fn real_agent_capture_status_tracks_remote_microphone_mute() {
    let fixture = Fixture::new();
    fixture.stub_workers();
    let _peer = Peer::new(&fixture, PeerBehavior::Compatible);
    let _agent = fixture.agent(None);
    let prepared = fixture.command("prepare", json!({}));
    assert_eq!(
        prepared.code,
        200,
        "mute regression setup requires compatible prepare: {}",
        prepared.json()
    );
    let started = fixture.command("start", json!({"output":"recording"}));
    assert_eq!(started.code, 200, "{}", started.json());
    for (action, muted) in [
        ("mute", true),
        ("status", true),
        ("unmute", false),
        ("status", false),
    ] {
        let response = fixture.command("mic", json!({"action":action}));
        assert_eq!(response.code, 200, "{}", response.json());
        assert_eq!(response.json()["muted"], muted);
        let status = fixture.get("/api/status").json();
        assert_eq!(status["state"], "running");
        assert_eq!(status["output"], "recording");
        assert_eq!(
            status["mic_muted"], muted,
            "capture status is stale after successful remote {action}: {status}"
        );
        let diagnostics = fixture.command("diagnostics", json!({}));
        assert_eq!(diagnostics.code, 200);
        assert_eq!(diagnostics.json()["mic_muted"], muted);
    }
    assert_eq!(fixture.command("stop", json!({})).code, 200);
    assert_idle(&fixture.get("/api/status").json());
}

#[test]
fn real_agent_status_cli_and_tui_leave_outputs_idle() {
    let fixture = Fixture::new();
    let _agent = fixture.agent(None);
    let response = fixture.get("/api/status");
    assert_eq!(response.code, 200);
    assert_idle(&response.json());
    response.no_secret();
    let (status, out, err) = fixture.cli(&["status"], b"");
    assert!(status.success(), "{err}");
    assert_idle(&serde_json::from_str(&out).unwrap());
    assert!(!out.contains(TOKEN));
    let (status, out, err) = fixture.cli(&["tui"], b"1\n0\n");
    assert!(status.success(), "{err}");
    assert!(out.contains("State idle"), "{out}");
    assert!(out.contains("game.av"), "routes missing: {out}");
    assert!(!out.contains("Operation failed"), "{out}");
    assert!(!out.contains(TOKEN));
    assert_idle(&fixture.get("/api/status").json());
}

#[test]
fn real_agent_rejects_authentication_and_ambiguous_http() {
    let fixture = Fixture::new();
    let _agent = fixture.agent(None);
    let headers = fixture.headers();
    let bad_headers = [
        headers.replace(TOKEN, "wrong-token"),
        headers.replace(
            &format!("Origin: http://127.0.0.1:{}", fixture.port),
            "Origin: https://evil.invalid",
        ),
        headers.replace(
            &format!("Host: 127.0.0.1:{}", fixture.port),
            "Host: evil.invalid",
        ),
        headers
            .lines()
            .filter(|line| !line.starts_with("Origin:"))
            .map(|line| format!("{}\r\n", line.trim_end()))
            .collect(),
        format!("{headers}Authorization: Bearer {TOKEN}\r\n"),
        format!("{headers}Host: 127.0.0.1:{}\r\n", fixture.port),
        format!("{headers}Content-Length: 0\r\nContent-Length: 0\r\n"),
        format!("{headers}Transfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n"),
        format!("{headers}Transfer-Encoding: chunked\r\nContent-Length: 0\r\n"),
    ];
    for headers in bad_headers {
        let response =
            fixture.exchange(format!("GET /api/status HTTP/1.1\r\n{headers}\r\n").as_bytes());
        assert_eq!(response.code, 403, "accepted {headers:?}");
        response.no_secret();
    }
    let smuggled = format!("POST /api/command HTTP/1.1\r\n{}Content-Type: application/json\r\nContent-Length: 2\r\n\r\n{{}}GET /api/status HTTP/1.1\r\n\r\n", fixture.headers());
    assert_eq!(fixture.exchange(smuggled.as_bytes()).code, 403);
    assert_eq!(fixture.post(&[0xff, 0xfe]).code, 403);
    let mut boundary = b"{\"command\":\"status\",\"args\":{}}".to_vec();
    boundary.resize(16 * 1024, b' ');
    assert_eq!(fixture.post(&boundary).code, 200, "16KiB is permitted");
    boundary.push(b' ');
    assert_eq!(
        fixture.post(&boundary).code,
        403,
        "over 16KiB must be rejected"
    );
    assert_idle(&fixture.get("/api/status").json());
}

#[test]
fn real_agent_rejects_unknown_commands_and_arguments_without_side_effects() {
    let fixture = Fixture::new();
    let _agent = fixture.agent(None);
    for body in [
        json!({"command":"not-a-command","args":{}}),
        json!({"command":"status","args":{"unexpected":true}}),
        json!({"command":"start","args":{"output":"public-network"}}),
        json!({"command":"status","args":{},"unexpected":true}),
    ] {
        let response = fixture.post(body.to_string().as_bytes());
        assert_eq!(response.code, 409, "accepted {body}");
        assert!(response.json()["error"].is_string());
        response.no_secret();
    }
    let (status, _, err) = fixture.cli(&["status", "--output", "twitch"], b"");
    assert!(!status.success());
    assert!(err.contains("unexpected extra arguments"), "{err}");
    assert_idle(&fixture.get("/api/status").json());
}

#[test]
fn slow_client_does_not_block_status_or_sigterm_and_role_lock_is_exclusive() {
    let fixture = Fixture::new();
    let mut agent = fixture.agent(None);
    let mut slow = TcpStream::connect(("127.0.0.1", fixture.port)).unwrap();
    slow.write_all(b"POST /api/command HTTP/1.1\r\nHost:")
        .unwrap();
    let start = Instant::now();
    assert_eq!(fixture.get("/api/status").code, 200);
    assert!(
        start.elapsed() < Duration::from_secs(2),
        "status waited for incomplete HTTP headers"
    );
    let mut other: Value = serde_json::from_slice(&fs::read(&fixture.config).unwrap()).unwrap();
    let reservation = TcpListener::bind("127.0.0.1:0").unwrap();
    other["peer"]["control_port"] = json!(reservation.local_addr().unwrap().port());
    let second_config = fixture.root.join("second.json");
    fs::write(&second_config, other.to_string()).unwrap();
    drop(reservation);
    let second_fixture = Fixture {
        _network: None,
        root: fixture.root.join("unused"),
        config: second_config,
        port: 0,
    };
    fs::create_dir(&second_fixture.root).unwrap();
    for _ in 0..3 {
        let (status, _, err) = second_fixture.cli(&["agent"], b"");
        assert!(!status.success());
        assert!(
            err.contains("already owns this role state directory"),
            "{err}"
        );
        assert_idle(&fixture.get("/api/status").json());
    }
    agent.terminate();
    let listener =
        TcpListener::bind(("127.0.0.1", fixture.port)).expect("SIGTERM releases control port");
    drop(listener);
    let mut restarted = fixture.agent(None);
    assert_idle(&fixture.get("/api/status").json());
    restarted.terminate();
}

#[test]
fn agent_refuses_world_readable_token_before_serving() {
    let fixture = Fixture::new();
    fs::set_permissions(
        fixture.root.join("control.token"),
        fs::Permissions::from_mode(0o644),
    )
    .unwrap();
    let (status, out, err) = fixture.cli(&["agent"], b"");
    assert!(!status.success());
    assert!(
        err.contains("credential must be a private file owned by this user"),
        "{err}"
    );
    assert!(!out.contains(TOKEN));
    assert!(!err.contains(TOKEN));
    assert!(TcpListener::bind(("127.0.0.1", fixture.port)).is_ok());
}

#[test]
fn fixed_wasm_assets_are_served_without_secrets_or_path_traversal() {
    let fixture = Fixture::new();
    let assets = fixture.root.join("assets");
    fs::create_dir(&assets).unwrap();
    for (name, body) in [
        (
            "index.html",
            b"<!doctype html><title>asset fixture</title>".as_slice(),
        ),
        ("loader.js", b"// asset fixture\n".as_slice()),
        (
            "splitcast_web.js",
            b"// generated glue fixture\n".as_slice(),
        ),
        ("splitcast_web_bg.wasm", b"\0asm\x01\0\0\0".as_slice()),
    ] {
        fs::write(assets.join(name), body).unwrap();
    }
    fs::write(fixture.root.join("outside-secret"), TOKEN).unwrap();
    let _agent = fixture.agent(Some(&assets));
    for (path, mime) in [
        ("/", "text/html"),
        ("/loader.js", "text/javascript"),
        ("/splitcast_web.js", "text/javascript"),
        ("/splitcast_web_bg.wasm", "application/wasm"),
    ] {
        let response = fixture.exchange(
            format!(
                "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\n\r\n",
                fixture.port
            )
            .as_bytes(),
        );
        assert_eq!(response.code, 200);
        assert!(response.head.contains(mime));
        assert!(response.head.contains("Cache-Control: no-store"));
        response.no_secret();
        let file = if path == "/" {
            "index.html"
        } else {
            &path[1..]
        };
        assert_eq!(response.body, fs::read(assets.join(file)).unwrap());
    }
    for path in [
        "/../outside-secret",
        "/%2e%2e/outside-secret",
        "/loader.js?token=private",
        "/control.token",
    ] {
        let response = fixture.get(path);
        assert_eq!(response.code, 404, "path mapped to filesystem: {path}");
        response.no_secret();
    }
}

#[test]
fn native_artifact_validates_toml_offline_without_agent_or_secrets() {
    let mut fixture = Fixture::new();
    let cfg: Value = serde_json::from_slice(&fs::read(&fixture.config).unwrap()).unwrap();
    let toml_value: toml::Value = serde_json::from_value(cfg).unwrap();
    fixture.config = fixture.root.join("config.toml");
    fs::write(&fixture.config, toml::to_string(&toml_value).unwrap()).unwrap();
    fs::remove_file(fixture.root.join("control.token")).unwrap();
    let (status, out, err) = fixture.cli(&["validate"], b"");
    assert!(status.success(), "{err}");
    assert_eq!(serde_json::from_str::<Value>(&out).unwrap()["valid"], true);
    assert!(!out.contains(TOKEN));
    assert!(TcpListener::bind(("127.0.0.1", fixture.port)).is_ok());
}

#[test]
fn cli_default_start_is_recording_and_redirects_are_not_followed() {
    let fixture = Fixture::new();
    let server = TcpListener::bind(("127.0.0.1", fixture.port)).unwrap();
    server.set_nonblocking(true).unwrap();
    let redirect_target = TcpListener::bind("127.0.0.1:0").unwrap();
    redirect_target.set_nonblocking(true).unwrap();
    let mut cli = fixture.spawn(&["start"], b"", None);
    let deadline = Instant::now() + LIMIT;
    let mut connection = loop {
        match server.accept() {
            Ok((stream, _)) => break stream,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                assert!(
                    Instant::now() < deadline,
                    "CLI did not send start: {}",
                    cli.stderr()
                );
                thread::sleep(Duration::from_millis(10));
            }
            Err(e) => panic!("{e}"),
        }
    };
    connection.set_read_timeout(Some(LIMIT)).unwrap();
    connection.set_write_timeout(Some(LIMIT)).unwrap();
    let mut request = Vec::new();
    loop {
        let mut byte = [0];
        connection.read_exact(&mut byte).unwrap();
        request.push(byte[0]);
        assert!(request.len() < 20 * 1024);
        if request.ends_with(b"\r\n\r\n") {
            break;
        }
    }
    let header = String::from_utf8(request).unwrap();
    let length: usize = header
        .lines()
        .find_map(|l| l.strip_prefix("Content-Length: "))
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    assert!(length <= 16 * 1024);
    let mut body = vec![0; length];
    connection.read_exact(&mut body).unwrap();
    assert_eq!(
        serde_json::from_slice::<Value>(&body).unwrap(),
        json!({"command":"start","args":{"output":"recording"}})
    );
    write!(connection, "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:{}/stolen\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", redirect_target.local_addr().unwrap().port()).unwrap();
    drop(connection);
    assert!(!cli.wait(LIMIT).success());
    assert!(cli.stderr().contains("no redirects permitted"));
    assert!(
        matches!(redirect_target.accept(), Err(e) if e.kind() == std::io::ErrorKind::WouldBlock),
        "CLI followed redirect with credentials"
    );
}
