//! Authenticated OBS WebSocket v5 control over loopback TCP only.
use crate::config::{secret, Config};
use crate::state::{atomic_file, private_directory};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{self, Read, Write};
use std::net::{Ipv4Addr, SocketAddrV4, TcpListener, TcpStream};
use std::time::{Duration, Instant};
use tungstenite::{Message, WebSocket, protocol::WebSocketConfig};

const LIMIT: usize = 4 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(5);

fn err(message: &str) -> io::Error { io::Error::other(message) }
fn remaining(deadline: Instant) -> io::Result<Duration> {
    deadline.checked_duration_since(Instant::now()).filter(|d| !d.is_zero())
        .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "OBS control deadline exceeded"))
}

// A message may require many syscalls (including continuation frames). Every
// syscall consumes the same deadline rather than renewing the timeout.
struct DeadlineStream { stream: TcpStream, deadline: Instant }
impl Read for DeadlineStream {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        self.stream.set_read_timeout(Some(remaining(self.deadline)?))?;
        self.stream.read(bytes).map_err(normalize_timeout)
    }
}
impl Write for DeadlineStream {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.stream.set_write_timeout(Some(remaining(self.deadline)?))?;
        self.stream.write(bytes).map_err(normalize_timeout)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.stream.set_write_timeout(Some(remaining(self.deadline)?))?;
        self.stream.flush().map_err(normalize_timeout)
    }
}
fn normalize_timeout(e: io::Error) -> io::Error {
    if matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut) {
        io::Error::new(io::ErrorKind::TimedOut, "OBS control deadline exceeded")
    } else { e }
}
fn websocket_error(e: tungstenite::Error) -> io::Error {
    match e {
        tungstenite::Error::Io(e) => normalize_timeout(e),
        // Never include peer payloads or authentication material in errors.
        tungstenite::Error::Capacity(_) => err("oversized OBS response"),
        _ => err("invalid or closed OBS WebSocket"),
    }
}
fn base64_sha(input: &[u8]) -> String { STANDARD.encode(Sha256::digest(input)) }
fn auth_string<'a>(hello: &'a Value, key: &str) -> io::Result<&'a str> {
    hello["d"]["authentication"][key].as_str()
        .filter(|s| !s.is_empty() && s.len() <= 4096)
        .ok_or_else(|| err("OBS authentication string required"))
}
fn response_data(response: &str) -> io::Result<Value> {
    let value: Value = serde_json::from_str(response).map_err(|_| err("invalid OBS JSON"))?;
    value["d"]["responseData"].as_object().map(|_| value["d"]["responseData"].clone())
        .ok_or_else(|| err("OBS response data required"))
}
fn output_method(output: &str) -> io::Result<&'static str> {
    match output {
        "recording" => Ok("GetRecordStatus"),
        "twitch" => Ok("GetStreamStatus"),
        _ => Err(err("unknown output")),
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct OutputStatus {
    pub active: bool,
    pub bytes: Option<u64>,
    pub frames: Option<u64>,
    pub duration_ms: Option<u64>,
}

pub struct Obs { socket: WebSocket<DeadlineStream>, seq: u64, failed: bool }
impl Obs {
    pub fn connect(cfg: &Config) -> io::Result<Self> {
        Self::connect_until(cfg, Instant::now() + TIMEOUT)
    }
    fn connect_until(cfg: &Config, deadline: Instant) -> io::Result<Self> {
        let password = secret(&cfg.obs_password, 4096)?;
        if password.len() < 16 { return Err(err("OBS password is missing or too short")); }
        let addr = SocketAddrV4::new(Ipv4Addr::LOCALHOST, cfg.obs_port);
        let stream = TcpStream::connect_timeout(&addr.into(), remaining(deadline)?.min(Duration::from_secs(2)))?;
        let stream = DeadlineStream { stream, deadline };
        let config = WebSocketConfig::default().max_message_size(Some(LIMIT))
            .max_frame_size(Some(LIMIT)).max_write_buffer_size(LIMIT + 1024);
        let (socket, _) = tungstenite::client::client_with_config(
            format!("ws://127.0.0.1:{}/", cfg.obs_port), stream, Some(config))
            .map_err(|e| match e {
                tungstenite::HandshakeError::Failure(e) => websocket_error(e),
                _ => err("OBS WebSocket handshake interrupted"),
            })?;
        let mut obs = Self { socket, seq: 0, failed: false };
        let hello = obs.next(deadline)?;
        if hello["op"].as_u64() != Some(0) { return Err(err("OBS WebSocket v5 Hello required")); }
        let salt = auth_string(&hello, "salt")?;
        let challenge = auth_string(&hello, "challenge")?;
        let secret = base64_sha(format!("{password}{salt}").as_bytes());
        let proof = base64_sha(format!("{secret}{challenge}").as_bytes());
        obs.send(&json!({"op":1,"d":{"rpcVersion":1,"authentication":proof,"eventSubscriptions":0}}), deadline)?;
        if obs.next(deadline)?["op"].as_u64() != Some(2) {
            return Err(err("OBS WebSocket authentication rejected"));
        }
        Ok(obs)
    }
    fn send(&mut self, value: &Value, deadline: Instant) -> io::Result<()> {
        remaining(deadline)?;
        let text = value.to_string();
        if text.len() > LIMIT { return Err(err("oversized OBS request")); }
        self.socket.get_mut().deadline = deadline;
        self.socket.send(Message::Text(text.into())).map_err(websocket_error)
    }
    fn next(&mut self, deadline: Instant) -> io::Result<Value> {
        loop {
            remaining(deadline)?;
            self.socket.get_mut().deadline = deadline;
            match self.socket.read().map_err(websocket_error)? {
                Message::Text(text) => return serde_json::from_str(text.as_str()).map_err(|_| err("invalid OBS JSON")),
                Message::Ping(_) | Message::Pong(_) => {},
                _ => return Err(err("OBS text message required")),
            }
        }
    }
    pub fn call(&mut self, name: &str, body: &str) -> io::Result<String> {
        self.call_until(name, body, Instant::now() + TIMEOUT)
    }
    fn call_until(&mut self, name: &str, body: &str, deadline: Instant) -> io::Result<String> {
        if self.failed { return Err(err("OBS connection must be re-established")); }
        if body.len() > LIMIT / 2 || name.len() > 256 { return Err(err("oversized OBS request")); }
        let body: Value = serde_json::from_str(body).map_err(|_| err("invalid OBS request JSON"))?;
        if !body.is_object() { return Err(err("OBS request object required")); }
        self.seq = self.seq.checked_add(1).ok_or_else(|| err("OBS request sequence exhausted"))?;
        let id = self.seq.to_string();
        let result = (|| {
            self.send(&json!({"op":6,"d":{"requestType":name,"requestId":id,"requestData":body}}), deadline)?;
            for _ in 0..64 {
                let answer = self.next(deadline)?;
                if answer["op"].as_u64() != Some(7) { continue; }
                if answer["d"]["requestId"].as_str() != Some(id.as_str()) { continue; }
                if answer["d"]["requestStatus"]["result"].as_bool() != Some(true) {
                    return Err(err("OBS request rejected"));
                }
                return Ok(answer.to_string());
            }
            Err(err("OBS request lost amidst other events"))
        })();
        // A timed-out fragmented exchange must never be reused for another request.
        if result.is_err() { self.failed = true; }
        result
    }
    fn has(&mut self, method: &str, list: &str, key: &str, needle: &str) -> io::Result<bool> {
        let response = response_data(&self.call(method, "{}")?)?;
        let entries = response[list].as_array().ok_or_else(|| err("OBS list required"))?;
        Ok(entries.iter().any(|entry| entry[key].as_str() == Some(needle)))
    }
    fn input(&mut self, name: &str, kind: &str, settings: Value) -> io::Result<()> {
        if !self.has("GetInputList", "inputs", "inputName", name)? {
            self.call("CreateInput", &json!({"sceneName":"SplitCast","inputName":name,"inputKind":kind,"inputSettings":settings,"sceneItemEnabled":true}).to_string())?;
        } else {
            self.call("SetInputSettings", &json!({"inputName":name,"inputSettings":settings,"overlay":false}).to_string())?;
        }
        Ok(())
    }
    pub fn configure(&mut self, cfg: &Config) -> io::Result<()> {
        self.call("GetVersion", "{}")?;
        if !self.has("GetSceneList", "scenes", "sceneName", "SplitCast")? {
            self.call("CreateScene", "{\"sceneName\":\"SplitCast\"}")?;
        }
        let feed = |name| json!({"is_local_file":false,"input":format!("rtsp://127.0.0.1:{}/{name}",cfg.rtsp),"input_format":"rtsp","ffmpeg_options":"rtsp_transport=tcp","hw_decode":true,"buffering_mb":1});
        self.input("GameFeed", "ffmpeg_source", feed("game"))?;
        self.input("MicProcessed", "pulse_input_capture", json!({"device_id":format!("{}.monitor",cfg.processed_sink)}))?;
        self.call("SetInputAudioSyncOffset", &json!({"inputName":"MicProcessed","inputAudioSyncOffset":cfg.mic_offset}).to_string())?;
        self.call("SetInputAudioMonitorType", "{\"inputName\":\"MicProcessed\",\"monitorType\":\"OBS_MONITORING_TYPE_NONE\"}")?;
        if cfg.camera_enabled { self.input("CameraFeed", "ffmpeg_source", feed("camera"))?; }
        self.input("Overlay", "text_ft2_source_v2", json!({"text":"SplitCast","font":{"face":"Sans","size":36}}))?;
        if cfg.tts_mix_remote { self.input("TTSMix", "ffmpeg_source", json!({"is_local_file":true,"local_file":""}))?; }
        self.call("SetCurrentProgramScene", "{\"sceneName\":\"SplitCast\"}")?;
        Ok(())
    }
    pub fn start(&mut self, cfg: &Config, output: &str) -> io::Result<()> {
        match output {
            "recording" => { self.call("StartRecord", "{}")?; },
            "twitch" => {
                let key = secret(&cfg.twitch_key, 4096)?;
                if key.is_empty() { return Err(err("Twitch key is empty")); }
                self.call("SetStreamServiceSettings", &json!({"streamServiceType":"rtmp_custom","streamServiceSettings":{"server":"rtmps://live.twitch.tv:443/app","key":key,"use_auth":false}}).to_string())?;
                self.call("StartStream", "{}")?;
            },
            _ => return Err(err("unknown output")),
        }
        Ok(())
    }
    pub fn stop(&mut self) -> io::Result<()> {
        for (output, stop) in [("recording", "StopRecord"), ("twitch", "StopStream")] {
            if self.status(output)? { self.call(stop, "{}")?; }
        }
        Ok(())
    }
    pub fn overlay(&mut self, text: &str) -> io::Result<()> {
        if text.chars().count() > 1000 { return Err(err("overlay too long")); }
        self.call("SetInputSettings", &json!({"inputName":"Overlay","inputSettings":{"text":text},"overlay":true}).to_string())?;
        Ok(())
    }
    pub fn observe(&mut self, output: &str) -> io::Result<OutputStatus> {
        let response = response_data(&self.call(output_method(output)?, "{}")?)?;
        Ok(OutputStatus {
            active: response["outputActive"].as_bool().ok_or_else(|| err("OBS outputActive boolean required"))?,
            bytes: response["outputBytes"].as_u64(),
            frames: response["outputTotalFrames"].as_u64(),
            duration_ms: response["outputDuration"].as_u64(),
        })
    }
    pub fn status(&mut self, output: &str) -> io::Result<bool> { Ok(self.observe(output)?.active) }
    pub fn preview(&mut self) -> io::Result<String> {
        let response = response_data(&self.call("GetSourceScreenshot", "{\"sourceName\":\"SplitCast\",\"imageFormat\":\"png\",\"imageWidth\":960,\"imageHeight\":540}")?)?;
        let image = response["imageData"].as_str().ok_or_else(|| err("OBS image required"))?;
        let encoded = image.strip_prefix("data:image/png;base64,").ok_or_else(|| err("invalid OBS preview format"))?;
        let data = STANDARD.decode(encoded).map_err(|_| err("invalid OBS preview base64"))?;
        if !data.starts_with(b"\x89PNG\r\n\x1a\n") { return Err(err("invalid OBS preview PNG data")); }
        Ok(json!({"image":image}).to_string())
    }
}

pub fn launch_args(cfg: &Config) -> io::Result<Vec<String>> {
    let _port = TcpListener::bind((Ipv4Addr::LOCALHOST, cfg.obs_port)).map_err(|_| err("OBS port is already occupied"))?;
    let base = cfg.state_dir.join("obs-config");
    let studio = base.join("obs-studio");
    let password = secret(&cfg.obs_password, 4096)?;
    if password.len() < 16 { return Err(err("OBS auth password must be at least 16 characters")); }
    private_directory(&cfg.state_dir)?;
    atomic_file(&studio.join("plugin_config/obs-websocket/config.json"), &json!({"server_enabled":true,"server_port":cfg.obs_port,"auth_required":true,"server_password":password,"first_load":false}).to_string())?;
    fs::create_dir_all(&cfg.recording_dir)?;
    if cfg.recording_dir.to_string_lossy().contains(['\n','\r']) { return Err(err("invalid recording directory")); }
    let profile = format!("[General]\nName=SplitCast\n[Video]\nBaseCX=1920\nBaseCY=1080\nOutputCX=1920\nOutputCY=1080\nFPSType=0\nFPSCommon=60\n[Output]\nMode=Advanced\n[AdvOut]\nEncoder=obs_nvenc_h264_tex\nRecType=Standard\nRecFilePath={}\nRecFormat2=mkv\nRecEncoder=obs_nvenc_h264_tex\nTrackIndex=1\nRecTracks=1\nRescale=false\n[Audio]\nSampleRate=48000\nChannelSetup=Stereo\n", cfg.recording_dir.display());
    atomic_file(&studio.join("basic/profiles/SplitCast/basic.ini"), &profile)?;
    atomic_file(&studio.join("user.ini"), "[Basic]\nProfile=SplitCast\nProfileDir=SplitCast\nSceneCollection=SplitCast\nSceneCollectionFile=SplitCast\n[General]\nFirstRun=true\n")?;
    atomic_file(&studio.join("basic/scenes/SplitCast.json"), "{\"name\":\"SplitCast\",\"current_scene\":\"SplitCast\",\"current_program_scene\":\"SplitCast\",\"scene_order\":[{\"name\":\"SplitCast\"}],\"sources\":[],\"groups\":[],\"transitions\":[]}")?;
    Ok(vec!["env".into(), format!("XDG_CONFIG_HOME={}", base.display()), cfg.obs_binary.to_string_lossy().to_string(), "--multi".into(), "--disable-shutdown-check".into(), "--profile".into(), "SplitCast".into(), "--collection".into(), "SplitCast".into()])
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, MetadataExt, PermissionsExt};
    use std::path::{Path, PathBuf};
    use std::thread;

    const PNG: &str = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8xkAAAAASUVORK5CYII=";
    struct Fixture { dir: PathBuf }
    impl Fixture {
        fn new() -> Self {
            static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
            let dir = PathBuf::from("/tmp/opencode").join(format!("native-obs-{}-{}",std::process::id(), NEXT.fetch_add(1,std::sync::atomic::Ordering::Relaxed)));
            private_directory(&dir).unwrap();
            atomic_file(&dir.join("password"), "a-private-password-long-enough").unwrap();
            Self { dir }
        }
        fn config(&self, port: u16) -> Config { config(&self.dir, port) }
    }
    impl Drop for Fixture { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.dir); } }
    fn config(dir: &Path, port: u16) -> Config {
        Config {
            document:String::new(), role:"production".into(),state_dir:dir.into(),token_file:dir.join("token"),remote_token_file:dir.join("token"),
            ssh_host:"localhost".into(),ssh_port:22,control_port:18001,remote_control_port:18002,forward_control_port:18003,timeout:1,retry_limit:0,
            rtmp:18004,rtsp:18005,api:18006,width:1920,height:1080,fps:60,bitrate:10000,target:String::new(),game_audio:String::new(),
            mic_source:String::new(),tts_sink:String::new(),processed_sink:"splitcast_mic".into(),rnnoise_plugin:dir.join("rnnoise"),
            rnnoise_label:String::new(),rnnoise_control:String::new(),gain_db:0,mic_offset:0,camera_enabled:false,camera_location:"production".into(),
            camera_mode:"h264".into(),camera_device:String::new(),camera_encoder:"h264_nvenc".into(),camera_hw:dir.into(),camera_width:640,camera_height:480,camera_fps:30,
            obs_binary:"obs".into(),obs_port:port,obs_password:dir.join("password"),twitch_key:dir.join("twitch"),recording_dir:dir.join("recordings"),
            tts_enabled:false,voicevox_url:String::new(),tts_speaker:0,tts_max_text:100,tts_queue_limit:1,tts_expiry_seconds:5,tts_credentials_file:dir.join("tts"),tts_mix_remote:false,eventsub_enabled:false,
        }
    }
    fn read(socket: &mut WebSocket<TcpStream>) -> Value {
        serde_json::from_str(socket.read().unwrap().to_text().unwrap()).unwrap()
    }
    fn send(socket: &mut WebSocket<TcpStream>, value: Value) {
        socket.send(Message::Text(value.to_string().into())).unwrap();
    }
    fn answer(socket: &mut WebSocket<TcpStream>, request: &Value, data: Value) {
        send(socket, json!({"op":7,"d":{"requestId":request["d"]["requestId"],"requestStatus":{"result":true},"responseData":data}}));
    }
    fn server(f: impl FnOnce(WebSocket<TcpStream>) + Send + 'static) -> (u16, thread::JoinHandle<()>) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let thread = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            stream.set_read_timeout(Some(TIMEOUT)).unwrap();
            stream.set_write_timeout(Some(TIMEOUT)).unwrap();
            let mut socket = tungstenite::accept(stream).unwrap();
            send(&mut socket, json!({"op":0,"d":{"authentication":{"salt":"salt\"","challenge":"challenge\\"}}}));
            let identify = read(&mut socket);
            let secret = base64_sha(b"a-private-password-long-enoughsalt\"");
            assert_eq!(identify["d"]["authentication"], base64_sha(format!("{secret}challenge\\").as_bytes()));
            assert_eq!(identify["d"]["eventSubscriptions"], 0);
            send(&mut socket, json!({"op":2,"d":{"negotiatedRpcVersion":1}}));
            f(socket);
        });
        (port, thread)
    }

    #[test]
    fn authenticates_and_decodes_preview_over_real_websocket() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            let request = read(&mut socket);
            assert_eq!(request["d"]["requestType"], "GetSourceScreenshot");
            answer(&mut socket, &request, json!({"imageData":PNG}));
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        assert_eq!(serde_json::from_str::<Value>(&obs.preview().unwrap()).unwrap()["image"], PNG);
        thread.join().unwrap();
    }
    #[test]
    fn wrong_ids_are_ignored_and_result_must_be_boolean() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            let request = read(&mut socket);
            send(&mut socket, json!({"op":7,"d":{"requestId":"wrong","requestStatus":{"result":true}}}));
            send(&mut socket, json!({"op":5}));
            send(&mut socket, json!({"op":7,"d":{"requestId":request["d"]["requestId"],"requestStatus":{"result":"true"}}}));
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        assert_eq!(obs.call("GetVersion", "{}").unwrap_err().to_string(), "OBS request rejected");
        assert!(obs.call("GetVersion", "{}").unwrap_err().to_string().contains("re-established"));
        thread.join().unwrap();
    }
    #[test]
    fn stalled_response_and_events_share_one_deadline() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            read(&mut socket);
            for _ in 0..20 {
                if socket.send(Message::Text("{\"op\":5}".into())).is_err() { break; }
                thread::sleep(Duration::from_millis(20));
            }
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        let start = Instant::now();
        assert_eq!(obs.call_until("GetVersion", "{}", start + Duration::from_millis(100)).unwrap_err().kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_millis(500));
        drop(obs); thread.join().unwrap();
    }
    #[test]
    fn dripfed_partial_frame_cannot_extend_deadline() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            read(&mut socket);
            let stream = socket.get_mut();
            stream.write_all(&[0x81, 126, 0, 200]).unwrap();
            for _ in 0..200 {
                if stream.write_all(b"x").is_err() { break; }
                thread::sleep(Duration::from_millis(10));
            }
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        let start = Instant::now();
        assert_eq!(obs.call_until("GetVersion", "{}", start + Duration::from_millis(100)).unwrap_err().kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_millis(500));
        drop(obs); thread.join().unwrap();
    }
    #[test]
    fn stalled_response_is_bounded() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            read(&mut socket);
            thread::sleep(Duration::from_millis(250));
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        let start = Instant::now();
        assert_eq!(obs.call_until("GetVersion", "{}", start + Duration::from_millis(100)).unwrap_err().kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_millis(500));
        drop(obs); thread.join().unwrap();
    }
    #[test]
    fn dripfed_http_upgrade_is_bounded() {
        let fixture = Fixture::new();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let cfg = fixture.config(listener.local_addr().unwrap().port());
        let thread = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream.set_read_timeout(Some(TIMEOUT)).unwrap();
            let mut request = Vec::new();
            while !request.ends_with(b"\r\n\r\n") {
                let mut byte = [0]; stream.read_exact(&mut byte).unwrap(); request.push(byte[0]);
            }
            for byte in b"HTTP/1.1 101 Switching Protocols\r\n" {
                if stream.write_all(&[*byte]).is_err() { break; }
                thread::sleep(Duration::from_millis(10));
            }
        });
        let start = Instant::now();
        let result = Obs::connect_until(&cfg, start + Duration::from_millis(100));
        assert_eq!(result.err().unwrap().kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_millis(500));
        thread.join().unwrap();
    }
    #[test]
    fn unauthenticated_server_is_rejected() {
        let fixture = Fixture::new();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let cfg = fixture.config(listener.local_addr().unwrap().port());
        let thread = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut socket = tungstenite::accept(stream).unwrap();
            send(&mut socket, json!({"op":0,"d":{"rpcVersion":1}}));
        });
        assert!(Obs::connect(&cfg).err().unwrap().to_string().contains("authentication string required"));
        thread.join().unwrap();
    }
    #[test]
    fn blocked_tcp_writes_share_one_deadline() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let stream = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (_peer, _) = listener.accept().unwrap();
        let start = Instant::now();
        let mut stream = DeadlineStream { stream, deadline: start + Duration::from_millis(100) };
        assert_eq!(stream.write_all(&vec![0; 32 * 1024 * 1024]).unwrap_err().kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_millis(500));
    }
    #[test]
    fn dripfed_continuations_cannot_extend_deadline() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            read(&mut socket);
            let stream = socket.get_mut();
            stream.write_all(&[0x01, 1, b'{']).unwrap();
            for _ in 0..100 {
                if stream.write_all(&[0x00, 1, b' ']).is_err() { break; }
                thread::sleep(Duration::from_millis(10));
            }
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        let start = Instant::now();
        assert_eq!(obs.call_until("GetVersion", "{}", start + Duration::from_millis(100)).unwrap_err().kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_millis(500));
        drop(obs); thread.join().unwrap();
    }
    #[test]
    fn oversized_frame_is_rejected_before_payload() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            read(&mut socket);
            socket.get_mut().write_all(&[0x81, 127, 0, 0, 0, 0, 0, 0x40, 0, 1]).unwrap();
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        assert!(obs.call("GetVersion", "{}").unwrap_err().to_string().contains("oversized"));
        thread.join().unwrap();
    }
    #[test]
    fn oversized_fragmented_message_is_rejected() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            read(&mut socket);
            let stream = socket.get_mut();
            // Two individually legal frames exceed the aggregate message limit.
            stream.write_all(&[0x01, 127, 0, 0, 0, 0, 0, 0x20, 0, 0]).unwrap();
            stream.write_all(&vec![b'x'; LIMIT / 2]).unwrap();
            stream.write_all(&[0x80, 127, 0, 0, 0, 0, 0, 0x20, 0, 1]).unwrap();
            let _ = stream.write_all(&vec![b'x'; LIMIT / 2 + 1]);
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        assert!(obs.call("GetVersion", "{}").unwrap_err().to_string().contains("oversized"));
        drop(obs); thread.join().unwrap();
    }
    #[test]
    fn exact_names_only_not_settings_or_substrings() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            let request = read(&mut socket);
            answer(&mut socket, &request, json!({"scenes":[{"sceneName":"SplitCastBackup"},{"sceneName":"Other","settings":"SplitCast"}]}));
            let request = read(&mut socket);
            answer(&mut socket, &request, json!({"inputs":[{"inputName":"GameFeedBackup"},{"inputName":"Other","settings":"GameFeed"}]}));
            let request = read(&mut socket);
            answer(&mut socket, &request, json!({"scenes":[{"sceneName":"SplitCast"}]}));
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        assert!(!obs.has("GetSceneList", "scenes", "sceneName", "SplitCast").unwrap());
        assert!(!obs.has("GetInputList", "inputs", "inputName", "GameFeed").unwrap());
        assert!(obs.has("GetSceneList", "scenes", "sceneName", "SplitCast").unwrap());
        thread.join().unwrap();
    }
    #[test]
    fn preview_requires_decodable_png_not_just_prefix() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            for image in ["data:image/png;base64,iVBORw0KGgoA===", "data:image/png;base64,aGVsbG8=", "data:image/jpeg;base64,iVBORw0KGgo="] {
                let request = read(&mut socket);
                answer(&mut socket, &request, json!({"imageData":image}));
            }
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        for _ in 0..3 { assert!(obs.preview().is_err()); }
        thread.join().unwrap();
    }
    #[test]
    fn output_status_reports_progress_and_rejects_unknown_output() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            let request = read(&mut socket);
            assert_eq!(request["d"]["requestType"], "GetRecordStatus");
            answer(&mut socket, &request, json!({"outputActive":true,"outputBytes":123,"outputTotalFrames":42,"outputDuration":99}));
        });
        let mut obs = Obs::connect(&fixture.config(port)).unwrap();
        assert!(obs.status("invalid").is_err());
        assert_eq!(obs.observe("recording").unwrap(), OutputStatus { active:true, bytes:Some(123), frames:Some(42), duration_ms:Some(99) });
        thread.join().unwrap();
    }
    #[test]
    fn recording_does_not_read_twitch_key_or_start_streaming() {
        let fixture = Fixture::new();
        let (port, thread) = server(|mut socket| {
            let request = read(&mut socket);
            assert_eq!(request["d"]["requestType"], "StartRecord");
            answer(&mut socket, &request, json!({}));
        });
        let cfg = fixture.config(port);
        assert!(!cfg.twitch_key.exists());
        let mut obs = Obs::connect(&cfg).unwrap();
        assert!(obs.start(&cfg, "unknown").is_err());
        assert!(obs.start(&cfg, "twitch").is_err());
        obs.start(&cfg, "recording").unwrap();
        thread.join().unwrap();
    }
    #[test]
    fn launch_refuses_occupied_port() {
        let fixture = Fixture::new();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        assert!(launch_args(&fixture.config(listener.local_addr().unwrap().port())).unwrap_err().to_string().contains("occupied"));
    }
    #[test]
    fn launch_refuses_public_credentials_and_keeps_generated_files_private() {
        let fixture = Fixture::new();
        let cfg = fixture.config(0);
        fs::set_permissions(&cfg.obs_password, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(launch_args(&cfg).is_err());
        fs::set_permissions(&cfg.obs_password, fs::Permissions::from_mode(0o600)).unwrap();
        launch_args(&cfg).unwrap();
        let credentials = cfg.state_dir.join("obs-config/obs-studio/plugin_config/obs-websocket/config.json");
        assert_eq!(fs::metadata(&credentials).unwrap().mode() & 0o777, 0o600);
        assert_eq!(fs::metadata(credentials.parent().unwrap()).unwrap().mode() & 0o777, 0o700);
        assert_eq!(fs::read_to_string(&cfg.obs_password).unwrap(), "a-private-password-long-enough");
    }
    #[test]
    fn atomic_state_rejects_symlinks_and_ignores_predictable_temp_symlink() {
        let fixture = Fixture::new();
        let victim = fixture.dir.join("victim");
        fs::write(&victim, "untouched").unwrap();
        let state = fixture.dir.join("state.json");
        symlink(&victim, state.with_extension("tmp")).unwrap();
        atomic_file(&state, "private").unwrap();
        assert_eq!(fs::read_to_string(&victim).unwrap(), "untouched");
        assert_eq!(fs::metadata(&state).unwrap().mode() & 0o777, 0o600);
        fs::remove_file(&state).unwrap();
        symlink(&victim, &state).unwrap();
        assert!(atomic_file(&state, "private").is_err());
        let alias = fixture.dir.join("alias");
        symlink(&fixture.dir, &alias).unwrap();
        assert!(atomic_file(&alias.join("other"), "private").is_err());
        assert_eq!(fs::read_to_string(victim).unwrap(), "untouched");
    }
}
