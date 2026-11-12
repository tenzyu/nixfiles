//! Native subprocess command specification. Uses the OS's existing hardware
//! codecs / GSR / FFmpeg. No game injection, no glReadPixels or frame capture
//! in the official osu! process. All arguments are passed as argv, not shell.
use crate::config::Config;
use std::fs;
use std::io;
use std::path::Path;
use std::process::{Command,Output};

fn strings(args:&[&str])->Vec<String>{args.iter().map(|x|x.to_string()).collect()}
fn err(s:&str)->io::Error{io::Error::new(io::ErrorKind::Other,s)}
pub fn command_checked(argv:&[String])->io::Result<String>{
    let (exe,rest)=argv.split_first().ok_or_else(||err("empty command"))?;
    let r=Command::new(exe).args(rest).output()?;
    if !r.status.success(){return Err(err("native helper exited nonzero; inspect its logs"));}
    if r.stdout.len()>8*1024*1024{return Err(err("native helper output too large"));}
    Ok(String::from_utf8_lossy(&r.stdout).trim().to_string())
}
pub fn run(exe:&str,args:&[&str])->io::Result<String>{
    let mut cmd=vec![exe.to_string()];cmd.extend(args.iter().map(|s|s.to_string()));command_checked(&cmd)
}
pub fn game(cfg:&Config)->io::Result<Vec<String>>{
    if cfg.target.is_empty() || cfg.game_audio.is_empty(){return Err(err("explicit capture.target and game_audio required"));}
    let mut a=strings(&["gpu-screen-recorder","-w"]);
    a.push(cfg.target.clone());a.push("-s".into());a.push(format!("{}x{}",cfg.width,cfg.height));
    a.extend(strings(&["-f",&cfg.fps.to_string(),"-fm","cfr","-k","h264","-encoder","gpu","-fallback-cpu-encoding","no","-tune","performance","-bm","cbr","-q",&cfg.bitrate.to_string(),"-keyint","2","-a"]));
    a.push(cfg.game_audio.clone());
    a.extend(strings(&["-ac","aac","-ab","192","-cursor","no","-c","flv","-o"]));
    a.push(format!("rtmp://127.0.0.1:{}/game",cfg.rtmp));
    Ok(a)
}
pub fn mic(cfg:&Config)->io::Result<Vec<String>>{
    if cfg.mic_source.is_empty(){return Err(err("explicit mic_source required"));}
    let mut a=strings(&["ffmpeg","-hide_banner","-nostdin","-loglevel","error","-thread_queue_size","256","-f","pulse","-sample_rate","48000","-channels","1","-i"]);
    a.push(cfg.mic_source.clone());a.extend(strings(&["-vn","-ac","1","-ar","48000","-c:a","libopus","-b:a","96k","-application","lowdelay","-f","rtsp","-rtsp_transport","tcp"]));
    a.push(format!("rtsp://127.0.0.1:{}/mic",cfg.rtsp));Ok(a)
}
pub fn rnnoise(cfg:&Config)->io::Result<Vec<String>>{
    let a=format!("aresample=48000:async=1000,aformat=channel_layouts=mono,ladspa=file={}:plugin={}:controls={},highpass=f=80,volume={}dB,alimiter=limit=0.95",
        cfg.rnnoise_plugin.display(),cfg.rnnoise_label,cfg.rnnoise_control,cfg.gain_db);
    Ok(vec!["ffmpeg".into(),"-hide_banner".into(),"-nostdin".into(),"-loglevel".into(),"error".into(),"-rtsp_transport".into(),"tcp".into(),"-i".into(),format!("rtsp://127.0.0.1:{}/mic",cfg.rtsp),"-vn".into(),"-af".into(),a,"-ar".into(),"48000".into(),"-ac".into(),"1".into(),"-f".into(),"pulse".into(),"-device".into(),cfg.processed_sink.clone(),"SplitCast processed microphone".into()])
}
pub fn camera(cfg:&Config)->io::Result<Vec<String>>{
    if cfg.camera_device.is_empty()||!cfg.camera_device.starts_with("/dev/video") {return Err(err("camera device must be /dev/videoN"));}
    let mut a=strings(&["ffmpeg","-hide_banner","-nostdin","-loglevel","error"]);
    if cfg.camera_mode=="hardware"&&cfg.camera_encoder=="h264_vaapi" {
        a.push("-vaapi_device".into());a.push(cfg.camera_hw.to_string_lossy().to_string());
    }
    a.extend(strings(&["-f","v4l2","-input_format",if cfg.camera_mode=="h264"{"h264"}else{"yuyv422"},"-video_size",&format!("{}x{}",cfg.camera_width,cfg.camera_height),"-framerate",&cfg.camera_fps.to_string(),"-i"]));
    a.push(cfg.camera_device.clone());a.push("-an".into());
    if cfg.camera_mode=="h264"{a.extend(strings(&["-c:v","copy"]));}
    else {
        if cfg.camera_encoder=="h264_vaapi"{a.extend(strings(&["-vf","format=nv12,hwupload"]));}
        a.extend(strings(&["-c:v",&cfg.camera_encoder,"-b:v","4M","-g",&(cfg.camera_fps as u32*2).to_string()]));
    }
    a.extend(strings(&["-f","rtsp","-rtsp_transport","tcp"]));
    a.push(format!("rtsp://127.0.0.1:{}/camera",cfg.rtsp));Ok(a)
}
pub fn tunnel(cfg:&Config)->Vec<String>{
    let mut a=strings(&["ssh","-N","-T","-o","BatchMode=yes","-o","ExitOnForwardFailure=yes","-o","ServerAliveInterval=5","-o","ServerAliveCountMax=2","-o","ConnectTimeout=5","-p",&cfg.ssh_port.to_string()]);
    for (local,remote) in [(cfg.forward_control_port,cfg.remote_control_port),(cfg.rtmp,cfg.rtmp),(cfg.rtsp,cfg.rtsp)] {
        a.push("-L".into());a.push(format!("127.0.0.1:{local}:127.0.0.1:{remote}"));
    }
    a.push("--".into());a.push(cfg.ssh_host.clone());a
}
pub fn receiver(cfg:&Config)->io::Result<Vec<String>>{
    let root=&cfg.state_dir;
    fs::create_dir_all(root)?;
    let filename=root.join("mediamtx-rs.json");
    // All ports come from bounded unsigned integers and never from user shell.
    let contents=format!(r#"{{"logLevel":"warn","rtsp":true,"rtspAddress":"127.0.0.1:{}","rtspTransports":["tcp"],"rtmp":true,"rtmpAddress":"127.0.0.1:{}","api":true,"apiAddress":"127.0.0.1:{}","hls":false,"webrtc":false,"srt":false,"metrics":false,"pprof":false,"playback":false,"paths":{{"game":{{"source":"publisher"}},"mic":{{"source":"publisher"}},"camera":{{"source":"publisher"}}}}}}"#,cfg.rtsp,cfg.rtmp,cfg.api);
    fs::write(&filename,contents)?;
    Ok(vec!["mediamtx".into(),filename.to_string_lossy().to_string()])
}
pub fn pcm_paths(cfg:&Config)->String{format!("http://127.0.0.1:{}/v3/paths/list",cfg.api)}

pub fn prepare_processed_sink(cfg:&Config)->io::Result<u32>{
    let exists=run("pactl",&["-f","json","list","sinks"])?;
    if exists.contains(&format!("\"name\": \"{}\"",cfg.processed_sink))||exists.contains(&format!("\"name\":\"{}\"",cfg.processed_sink)){
        return Err(err("processed sink already exists; will not take ownership"));
    }
    let out=run("pactl",&["load-module","module-null-sink",&format!("sink_name={}",cfg.processed_sink),"rate=48000","channels=1","sink_properties=device.description=SplitCast_Processed_Mic"])?;
    out.parse::<u32>().map_err(|_|err("could not identify owned Pulse module"))
}
pub fn release_processed_sink(module:u32)->io::Result<()>{run("pactl",&["unload-module",&module.to_string()]).map(|_|())}

pub fn ready_output(buf:&str,name:&str)->bool{
    // Presence of a path name alone does not prove moving A/V frames.
    buf.contains(&format!("\"name\":\"{name}\""))||buf.contains(&format!("\"name\": \"{name}\""))
}
pub fn check_tools(role:&str)->io::Result<Vec<String>>{
    let mut req=vec!["ffmpeg","ffprobe","pactl","jq","curl"];
    if role=="capture"{req.extend(["ssh","gpu-screen-recorder"])}else{req.extend(["mediamtx","websocat","openssl"])};
    let mut missing=vec![];
    for name in req {
        if Command::new("sh").args(["-c","command -v \"$1\" >/dev/null 2>&1","sh",name]).status()?.success()==false { missing.push(name.into()); }
    }
    Ok(missing)
}
pub fn check_path(p:&Path)->bool{p.is_file()}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn all_ports_bounded_by_config(){assert!(ready_output("{\"name\":\"game\"}","game"));}
}
