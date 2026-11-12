//! Strictly bounded, version-1 SplitCast configuration. Parsing is delegated
//! to the system jq executable (not to the legacy Python runtime).
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

fn error(msg: &str) -> io::Error { io::Error::new(io::ErrorKind::InvalidInput, msg) }

pub fn json_string(s: &str) -> String {
    let mut out=String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""), '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"), '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32)<32 => out.push_str(&format!("\\u{:04x}",c as u32)),
            c => out.push(c),
        }
    }
    out.push('"'); out
}

pub fn jq(file: &Path, filter: &str) -> io::Result<String> {
    let result=Command::new("jq").args(["-erc",filter])
        .arg(file).output()?;
    if !result.status.success() {
        return Err(error("SplitCast config failed JSON/required-field validation"));
    }
    Ok(String::from_utf8_lossy(&result.stdout).trim_end().to_string())
}
fn get(file: &Path, key: &str) -> io::Result<String> {
    // The caller supplies only fixed compile-time key names, never user data.
    let output=jq(file,&format!("{key} | if type==\"string\" then . else error(\"string required\") end"))?;
    // jq -c returns quoted string, but -r is intentionally not used here.
    // Decode via jq to avoid treating any escape sequence as a filesystem path.
    let out=Command::new("jq").args(["-er",key]).arg(file).output()?;
    if !out.status.success(){return Err(error("missing config string"));}
    let value=String::from_utf8_lossy(&out.stdout).trim_end_matches(['\n','\r']).to_string();
    if output == "null" || value.contains('\0') {return Err(error("invalid config string"));}
    Ok(value)
}
fn number(file:&Path,key:&str,min:u16,max:u16)->io::Result<u16>{
    let x=jq(file,&format!("{key} | if type==\"number\" and (. | floor)==. then . else error(\"integer\") end"))?;
    let n=x.parse::<u16>().map_err(|_|error("invalid integer"))?;
    if n<min || n>max{return Err(error("integer out of range"));} Ok(n)
}
fn boolean(file:&Path,key:&str)->io::Result<bool>{
    let s=jq(file,&format!("{key} | if type==\"boolean\" then . else error(\"bool\") end"))?;
    Ok(s=="true")
}
fn safe_name(s:&str)->bool{!s.is_empty()&&s.len()<=256&&s.bytes().all(|b|b.is_ascii_alphanumeric()||b"._:-".contains(&b))}
fn path(s: String) -> PathBuf {
    if s=="~" {return dirs_home();}
    if let Some(rest)=s.strip_prefix("~/") {return dirs_home().join(rest);}
    PathBuf::from(s)
}
fn dirs_home()->PathBuf{std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(||PathBuf::from("/nonexistent"))}

#[derive(Clone,Debug)]
pub struct Config {
    pub role:String,
    pub state_dir:PathBuf,
    pub token_file:PathBuf,
    pub remote_token_file:PathBuf,
    pub ssh_host:String,
    pub ssh_port:u16,
    pub control_port:u16,
    pub remote_control_port:u16,
    pub forward_control_port:u16,
    pub timeout:u16,
    pub rtmp:u16,
    pub rtsp:u16,
    pub api:u16,
    pub width:u16,
    pub height:u16,
    pub fps:u16,
    pub bitrate:u16,
    pub target:String,
    pub game_audio:String,
    pub mic_source:String,
    pub processed_sink:String,
    pub rnnoise_plugin:PathBuf,
    pub rnnoise_label:String,
    pub rnnoise_control:String,
    pub gain_db:i32,
    pub mic_offset:i32,
    pub camera_enabled:bool,
    pub camera_location:String,
    pub camera_mode:String,
    pub camera_device:String,
    pub camera_encoder:String,
    pub camera_hw:PathBuf,
    pub camera_width:u16,
    pub camera_height:u16,
    pub camera_fps:u16,
    pub obs_binary:PathBuf,
    pub obs_port:u16,
    pub obs_password:PathBuf,
    pub twitch_key:PathBuf,
    pub recording_dir:PathBuf,
    pub tts_enabled:bool,
    pub voicevox_url:String,
    pub tts_speaker:u16,
    pub tts_max_text:u16,
    pub tts_queue_limit:u16,
    pub tts_mix_remote:bool,
    pub eventsub_enabled:bool,
}
impl Config {
    pub fn load(filename:&Path)->io::Result<Self>{
        // Reject unknown top-level sections and unknown role, but do not trust
        // this as a complete JSON-Schema implementation. Route schema parity
        // is a separate acceptance gate.
        let checks=r#".version == 1 and (.role == "capture" or .role == "production") and
           ((keys - ["version","role","peer","capture","audio","camera","obs","tts","routes"])|length)==0 and
           (.routes|type)=="array" and (.routes|length)==5"#;
        if jq(filename,checks)? != "true" {return Err(error("unsupported SplitCast config"));}
        let role=get(filename,".role")?;
        let ssh_host=get(filename,".peer.ssh_host")?;
        if ssh_host.len()>253||!ssh_host.bytes().all(|b|b.is_ascii_alphanumeric()||b"._@-".contains(&b)) ||ssh_host.starts_with('-') {
            return Err(error("invalid ssh_host"));
        }
        let target=get(filename,".capture.target")?;
        let game_audio=get(filename,".capture.game_audio")?;
        let mic_source=get(filename,".audio.mic_source")?;
        let processed_sink=get(filename,".audio.processed_sink")?;
        if !processed_sink.starts_with("splitcast_") || !safe_name(&processed_sink) { return Err(error("unsafe processed sink")); }
        for v in [&target,&game_audio,&mic_source] {
            if !v.is_empty() && !safe_name(v) {return Err(error("unsafe capture/device identifier"));}
        }
        let rnnoise_plugin=path(get(filename,".audio.rnnoise_plugin")?);
        if !rnnoise_plugin.is_absolute()||!rnnoise_plugin.to_string_lossy().bytes().all(|b|b.is_ascii_alphanumeric()||b"/._+-".contains(&b)){
            return Err(error("unsafe RNNoise LADSPA path"));
        }
        let rnnoise_label=get(filename,".audio.rnnoise_label")?;
        let rnnoise_control=get(filename,".audio.rnnoise_control")?;
        if !safe_name(&rnnoise_label)||!rnnoise_control.bytes().all(|b|b.is_ascii_digit()||b".|-".contains(&b)) {return Err(error("unsafe RNNoise filter"));}
        let gain_db=number(filename,".audio.gain_db + 30",0,50)? as i32 - 30;
        let mic_offset=number(filename,".audio.mic_offset_ms + 2000",0,4000)? as i32 - 2000;
        let camera_location=get(filename,".camera.location")?;
        let camera_mode=get(filename,".camera.mode")?;
        let camera_encoder=get(filename,".camera.encoder")?;
        if !["capture","production"].contains(&camera_location.as_str())||!["hardware","h264"].contains(&camera_mode.as_str())||!["h264_vaapi","h264_nvenc"].contains(&camera_encoder.as_str()) {return Err(error("invalid camera mode"));}
        Ok(Self {
            role, ssh_host, state_dir:path(get(filename,".peer.state_dir")?),
            token_file:path(get(filename,".peer.token_file")?),
            remote_token_file:path(get(filename,".peer.remote_token_file")?),
            ssh_port:number(filename,".peer.ssh_port",1,65535)?,
            control_port:number(filename,".peer.control_port",1024,65535)?,
            remote_control_port:number(filename,".peer.remote_control_port",1024,65535)?,
            forward_control_port:number(filename,".peer.forward_control_port",1024,65535)?,
            timeout:number(filename,".peer.timeout_seconds",1,60)?,
            rtmp:number(filename,".capture.rtmp_port",1024,65535)?,
            rtsp:number(filename,".capture.rtsp_port",1024,65535)?,
            api:number(filename,".capture.api_port",1024,65535)?,
            width:number(filename,".capture.width",320,3840)?,
            height:number(filename,".capture.height",240,2160)?,
            fps:number(filename,".capture.fps",30,60)?,
            bitrate:number(filename,".capture.bitrate_kbps",1000,50000)?,
            target,game_audio,mic_source,processed_sink,rnnoise_plugin,rnnoise_label,rnnoise_control,gain_db,mic_offset,
            camera_enabled:boolean(filename,".camera.enabled")?,
            camera_location,camera_mode,camera_encoder,
            camera_device:get(filename,".camera.device")?,
            camera_hw:path(get(filename,".camera.hw_device")?),
            camera_width:number(filename,".camera.width",160,3840)?,
            camera_height:number(filename,".camera.height",120,2160)?,
            camera_fps:number(filename,".camera.fps",1,60)?,
            obs_binary:path(get(filename,".obs.binary")?),
            obs_port:number(filename,".obs.websocket_port",1024,65535)?,
            obs_password:path(get(filename,".obs.password_file")?),
            twitch_key:path(get(filename,".obs.twitch_key_file")?),
            recording_dir:path(get(filename,".obs.recording_dir")?),
            tts_enabled:boolean(filename,".tts.enabled")?,
            voicevox_url:get(filename,".tts.voicevox_url")?,
            tts_speaker:number(filename,".tts.speaker",0,10000)?,
            tts_max_text:number(filename,".tts.max_text",1,500)?,
            tts_queue_limit:number(filename,".tts.queue_limit",1,32)?,
            tts_mix_remote:boolean(filename,".tts.mix_remote")?,
            eventsub_enabled:boolean(filename,".tts.eventsub")?,
        })
    }
    pub fn token(&self,remote:bool)->io::Result<String>{
        let p=if remote{&self.remote_token_file}else{&self.token_file};
        let m=fs::metadata(p)?;
        if m.permissions().mode() & 0o077 != 0 {return Err(error("token permissions must be 0600"));}
        let s=fs::read_to_string(p)?.trim().to_string();
        if s.len()<24||s.len()>512||s.contains('\n'){return Err(error("invalid secret token length"));}
        Ok(s)
    }
}

#[cfg(test)] mod tests { use super::*; #[test] fn json_escaping(){assert_eq!(json_string("a\"b\n"),"\"a\\\"b\\n\"");} }
