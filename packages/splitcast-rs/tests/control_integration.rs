#![cfg(unix)]

use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const BIN: &str = env!("CARGO_BIN_EXE_splitcast-rs-core");
const TOKEN: &str = "integration-private-token-never-serialize";
const LIMIT: Duration = Duration::from_secs(5);
static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Fixture {
    root: PathBuf,
    config: PathBuf,
    port: u16,
}

impl Fixture {
    fn new() -> Self {
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
        // Reserve distinct ports together so the config itself cannot collide.
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
    assert!(err.contains("credential must be a private file owned by this user"), "{err}");
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
