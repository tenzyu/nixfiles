//! OBS WebSocket v5 controller, with authentication on loopback only.
//! Uses websocat and OpenSSL CLI instead of embedding a TLS/WebSocket stack in
//! the real-time capture process. This is control-plane I/O on neko7 only.
use crate::config::{Config,json_string};
use crate::media::command_checked;
use std::fs;
use std::io::{self,BufRead,BufReader,Write};
use std::net::{Ipv4Addr,SocketAddrV4,TcpStream};
use std::os::unix::fs::PermissionsExt;
use std::process::{Child,ChildStdin,ChildStdout,Command,Stdio};
use std::time::Duration;

fn err(msg:&str)->io::Error{io::Error::new(io::ErrorKind::Other,msg)}
fn json_lookup(payload:&str,filter:&str)->io::Result<String>{
    let mut cmd=Command::new("jq").args(["-erc",filter]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    cmd.stdin.take().unwrap().write_all(payload.as_bytes())?;
    let out=cmd.wait_with_output()?;
    if !out.status.success(){return Err(err("malformed OBS WebSocket response"));}
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
fn base64_sha(input:&[u8])->io::Result<String>{
    let mut cmd=Command::new("openssl").args(["dgst","-sha256","-binary"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    cmd.stdin.take().unwrap().write_all(input)?;
    let digest=cmd.wait_with_output()?;
    if !digest.status.success() || digest.stdout.len()!=32{return Err(err("openssl SHA256 failed"));}
    let mut b64=Command::new("base64").args(["-w0"]).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn()?;
    b64.stdin.take().unwrap().write_all(&digest.stdout)?;
    let out=b64.wait_with_output()?;
    if !out.status.success(){return Err(err("base64 failed"));}
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
fn unwrap_json_string(s:&str)->String{
    // Used only for ASCII salt/challenge; these have no JSON escape sequences.
    s.trim_matches('"').to_string()
}
pub struct Obs {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
    seq:u64,
}
impl Obs {
    pub fn connect(cfg:&Config)->io::Result<Self>{
        // Never connect to a LAN/tailnet OBS WebSocket. SSH forwarding happens
        // only for the control agent; OBS is bound to 127.0.0.1.
        let addr=SocketAddrV4::new(Ipv4Addr::LOCALHOST,cfg.obs_port);
        TcpStream::connect_timeout(&addr.into(),Duration::from_secs(2))?;
        let mut child=Command::new("websocat")
            .arg("-t").arg(format!("ws://127.0.0.1:{}",cfg.obs_port))
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
        let input=child.stdin.take().ok_or_else(||err("OBS websocket stdin unavailable"))?;
        let output=BufReader::new(child.stdout.take().ok_or_else(||err("OBS websocket stdout unavailable"))?);
        let mut obs=Self{child,input,output,seq:0};
        let hello=obs.next()?;
        if json_lookup(&hello,".op")?!="0" {return Err(err("OBS WebSocket v5 Hello required"));}
        let salt=json_lookup(&hello,".d.authentication.salt")?;
        let challenge=json_lookup(&hello,".d.authentication.challenge")?;
        if salt=="null"||challenge=="null" {return Err(err("dedicated OBS authentication required"));}
        let password=fs::read_to_string(&cfg.obs_password)?.trim().to_string();
        if password.len()<16{return Err(err("OBS password is missing or too short"));}
        let secret=base64_sha(format!("{}{}",password,unwrap_json_string(&salt)).as_bytes())?;
        let proof=base64_sha(format!("{}{}",secret,unwrap_json_string(&challenge)).as_bytes())?;
        obs.send(&format!("{{\"op\":1,\"d\":{{\"rpcVersion\":1,\"authentication\":{}}}}}",json_string(&proof)))?;
        if json_lookup(&obs.next()?,".op")?!="2" {return Err(err("OBS WebSocket authentication rejected"));}
        Ok(obs)
    }
    fn send(&mut self,text:&str)->io::Result<()>{
        self.input.write_all(text.as_bytes())?;self.input.write_all(b"\n")?;self.input.flush()
    }
    fn next(&mut self)->io::Result<String>{
        let mut line=String::new();
        self.output.read_line(&mut line)?;
        if line.is_empty()||line.len()>4*1024*1024{return Err(err("OBS websocket closed/oversized response"));}
        Ok(line)
    }
    pub fn call(&mut self,name:&str,body:&str)->io::Result<String>{
        self.seq+=1;let id=self.seq.to_string();
        let request=format!("{{\"op\":6,\"d\":{{\"requestType\":{},\"requestId\":{},\"requestData\":{}}}}}",json_string(name),json_string(&id),body);
        self.send(&request)?;
        for _ in 0..64 {
            let answer=self.next()?;
            if json_lookup(&answer,".op")?!="7"{continue;}
            if json_lookup(&answer,".d.requestId")?!=json_string(&id){continue;}
            if json_lookup(&answer,".d.requestStatus.result")?!="true"{return Err(err("OBS request rejected"));}
            return Ok(answer)
        }
        Err(err("OBS request lost amidst other events"))
    }
    fn has(&mut self,method:&str,key:&str,needle:&str)->io::Result<bool>{
        let response=self.call(method,"{}")?;
        Ok(json_lookup(&response,key)?.contains(&json_string(needle)))
    }
    fn input(&mut self,name:&str,kind:&str,settings:&str)->io::Result<()> {
        let encoded=json_string(name);
        if !self.has("GetInputList",".d.responseData.inputs",name)? {
            self.call("CreateInput",&format!("{{\"sceneName\":\"SplitCast\",\"inputName\":{encoded},\"inputKind\":{},\"inputSettings\":{settings},\"sceneItemEnabled\":true}}",json_string(kind)))?;
        }else{
            self.call("SetInputSettings",&format!("{{\"inputName\":{encoded},\"inputSettings\":{settings},\"overlay\":false}}"))?;
        }
        Ok(())
    }
    pub fn configure(&mut self,cfg:&Config)->io::Result<()> {
        self.call("GetVersion","{}")?;
        if !self.has("GetSceneList",".d.responseData.scenes","SplitCast")? {
            self.call("CreateScene","{\"sceneName\":\"SplitCast\"}")?;
        }
        // Configuring from explicit RTSP loopback paths avoids screen capture
        // inside OBS and does not modify the running osu! process.
        let game=format!("{{\"is_local_file\":false,\"input\":\"rtsp://127.0.0.1:{}/game\",\"input_format\":\"rtsp\",\"ffmpeg_options\":\"rtsp_transport=tcp\",\"hw_decode\":true,\"buffering_mb\":1}}",cfg.rtsp);
        self.input("GameFeed","ffmpeg_source",&game)?;
        let mic=format!("{{\"device_id\":{}}}",json_string(&format!("{}.monitor",cfg.processed_sink)));
        self.input("MicProcessed","pulse_input_capture",&mic)?;
        self.call("SetInputAudioSyncOffset",&format!("{{\"inputName\":\"MicProcessed\",\"inputAudioSyncOffset\":{}}}",cfg.mic_offset))?;
        self.call("SetInputAudioMonitorType","{\"inputName\":\"MicProcessed\",\"monitorType\":\"OBS_MONITORING_TYPE_NONE\"}")?;
        if cfg.camera_enabled {
            let cam=format!("{{\"is_local_file\":false,\"input\":\"rtsp://127.0.0.1:{}/camera\",\"input_format\":\"rtsp\",\"ffmpeg_options\":\"rtsp_transport=tcp\",\"hw_decode\":true,\"buffering_mb\":1}}",cfg.rtsp);
            self.input("CameraFeed","ffmpeg_source",&cam)?;
        }
        self.input("Overlay","text_ft2_source_v2","{\"text\":\"SplitCast\",\"font\":{\"face\":\"Sans\",\"size\":36}}")?;
        if cfg.tts_mix_remote {self.input("TTSMix","ffmpeg_source","{\"is_local_file\":true,\"local_file\":\"\"}")?;}
        self.call("SetCurrentProgramScene","{\"sceneName\":\"SplitCast\"}")?;
        Ok(())
    }
    pub fn start(&mut self,cfg:&Config,output:&str)->io::Result<()> {
        if output=="recording"{self.call("StartRecord","{}")?;return Ok(());}
        if output!="twitch"{return Err(err("unknown output"));}
        let key=fs::read_to_string(&cfg.twitch_key)?.trim().to_string();
        if key.is_empty(){return Err(err("Twitch key missing"));}
        let request=format!("{{\"streamServiceType\":\"rtmp_custom\",\"streamServiceSettings\":{{\"server\":\"rtmps://live.twitch.tv:443/app\",\"key\":{},\"use_auth\":false}}}}",json_string(&key));
        self.call("SetStreamServiceSettings",&request)?;
        self.call("StartStream","{}")?;Ok(())
    }
    pub fn stop(&mut self)->io::Result<()> {
        for (status,stop) in [("GetRecordStatus","StopRecord"),("GetStreamStatus","StopStream")] {
            let ret=self.call(status,"{}")?;
            if json_lookup(&ret,".d.responseData.outputActive")?=="true" {self.call(stop,"{}")?;}
        }Ok(())
    }
    pub fn overlay(&mut self,text:&str)->io::Result<()> {
        if text.chars().count()>1000 {return Err(err("overlay too long"));}
        self.call("SetInputSettings",&format!("{{\"inputName\":\"Overlay\",\"inputSettings\":{{\"text\":{}}},\"overlay\":true}}",json_string(text)))?;Ok(())
    }
    pub fn status(&mut self,output:&str)->io::Result<bool>{
        let method=if output=="recording"{"GetRecordStatus"}else{"GetStreamStatus"};
        let ret=self.call(method,"{}")?;
        Ok(json_lookup(&ret,".d.responseData.outputActive")?=="true")
    }
}
impl Drop for Obs {fn drop(&mut self){let _=self.child.kill();let _=self.child.wait();}}

fn atomic_file(p:&std::path::Path,s:&str)->io::Result<()> {
    let dir=p.parent().ok_or_else(||err("invalid state path"))?;
    fs::create_dir_all(dir)?;
    let part=p.with_extension("tmp");
    fs::write(&part,s)?;
    fs::set_permissions(&part,fs::Permissions::from_mode(0o600))?;
    fs::rename(part,p)?;Ok(())
}
pub fn launch_args(cfg:&Config)->io::Result<Vec<String>>{
    // A dedicated profile avoids contaminating the user's OBS installation.
    let base=cfg.state_dir.join("obs-config");let studio=base.join("obs-studio");
    let password=fs::read_to_string(&cfg.obs_password)?.trim().to_string();
    if password.len()<16 {return Err(err("OBS auth password must be at least 16 characters"));}
    atomic_file(&studio.join("plugin_config/obs-websocket/config.json"),&format!("{{\"server_enabled\":true,\"server_port\":{},\"auth_required\":true,\"server_password\":{},\"first_load\":false}}",cfg.obs_port,json_string(&password)))?;
    fs::create_dir_all(&cfg.recording_dir)?;
    let profile=format!("[General]\nName=SplitCast\n[Video]\nBaseCX=1920\nBaseCY=1080\nOutputCX=1920\nOutputCY=1080\nFPSType=0\nFPSCommon=60\n[Output]\nMode=Advanced\n[AdvOut]\nEncoder=obs_nvenc_h264_tex\nRecType=Standard\nRecFilePath={}\nRecFormat2=mkv\nRecEncoder=obs_nvenc_h264_tex\nTrackIndex=1\nRecTracks=1\nRescale=false\n[Audio]\nSampleRate=48000\nChannelSetup=Stereo\n",cfg.recording_dir.display());
    atomic_file(&studio.join("basic/profiles/SplitCast/basic.ini"),&profile)?;
    atomic_file(&studio.join("user.ini"),"[Basic]\nProfile=SplitCast\nProfileDir=SplitCast\nSceneCollection=SplitCast\nSceneCollectionFile=SplitCast\n[General]\nFirstRun=true\n")?;
    atomic_file(&studio.join("basic/scenes/SplitCast.json"),"{\"name\":\"SplitCast\",\"current_scene\":\"SplitCast\",\"current_program_scene\":\"SplitCast\",\"scene_order\":[{\"name\":\"SplitCast\"}],\"sources\":[],\"groups\":[],\"transitions\":[]}")?;
    // The OBS process must be a child owned by the systemd user service.
    Ok(vec!["env".into(),format!("XDG_CONFIG_HOME={}",base.display()),cfg.obs_binary.to_string_lossy().to_string(),"--multi".into(),"--disable-shutdown-check".into(),"--profile".into(),"SplitCast".into(),"--collection".into(),"SplitCast".into()])
}
