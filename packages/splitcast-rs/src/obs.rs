//! OBS WebSocket v5 controller, with authentication on loopback only.
//! Uses websocat and OpenSSL CLI instead of embedding a TLS/WebSocket stack in
//! the real-time capture process. This is control-plane I/O on neko7 only.
use crate::config::{Config,json_string,secret};
use std::fs;
use std::io::{self,Read,Write};
use std::net::{Ipv4Addr,SocketAddrV4,TcpStream,TcpListener};
use std::os::fd::{AsRawFd,RawFd};
use std::os::unix::fs::{DirBuilderExt,OpenOptionsExt,PermissionsExt,MetadataExt};
use std::process::{Child,ChildStdin,ChildStdout,Command,Stdio};
use std::time::{Duration,Instant};

const LIMIT:usize=4*1024*1024;
const TIMEOUT:Duration=Duration::from_secs(5);
const F_GETFL:i32=3;
const F_SETFL:i32=4;
const O_NONBLOCK:i32=0x800;
const O_DIRECTORY:i32=0x10000;
const O_NOFOLLOW:i32=0x20000;
const POLLIN:i16=1;
const POLLOUT:i16=4;
#[repr(C)]
struct PollFd{fd:RawFd,events:i16,revents:i16}
unsafe extern "C" {
    fn poll(fds:*mut PollFd,nfds:usize,timeout:i32)->i32;
    fn fcntl(fd:RawFd,cmd:i32,...)->i32;
}
fn nonblocking(fd:RawFd)->io::Result<()> {
    let flags=unsafe{fcntl(fd,F_GETFL)};
    if flags<0 || unsafe{fcntl(fd,F_SETFL,flags|O_NONBLOCK)}<0{return Err(io::Error::last_os_error());}
    Ok(())
}
fn poll_until(fds:&mut [PollFd],deadline:Instant)->io::Result<()> {
    loop {
        let left=deadline.checked_duration_since(Instant::now()).ok_or_else(||io::Error::new(io::ErrorKind::TimedOut,"OBS control deadline exceeded"))?;
        let ms=left.as_millis().saturating_add(1).min(i32::MAX as u128) as i32;
        let result=unsafe{poll(fds.as_mut_ptr(),fds.len(),ms)};
        if result>0{return Ok(());}
        if result==0{continue;}
        let error=io::Error::last_os_error();
        if error.kind()!=io::ErrorKind::Interrupted{return Err(error);}
    }
}
fn write_until<T:Write+AsRawFd>(output:&mut T,mut bytes:&[u8],deadline:Instant)->io::Result<()> {
    while !bytes.is_empty() {
        poll_until(&mut [PollFd{fd:output.as_raw_fd(),events:POLLOUT,revents:0}],deadline)?;
        match output.write(bytes) {
            Ok(0)=>return Err(err("OBS control pipe closed")),
            Ok(n)=>bytes=&bytes[n..],
            Err(e) if matches!(e.kind(),io::ErrorKind::WouldBlock|io::ErrorKind::Interrupted)=>{},
            Err(e)=>return Err(e),
        }
    }
    Ok(())
}
struct Lines<R>{reader:R,pending:Vec<u8>}
impl<R:Read+AsRawFd> Lines<R> {
    fn new(reader:R)->io::Result<Self>{nonblocking(reader.as_raw_fd())?;Ok(Self{reader,pending:Vec::new()})}
    fn next(&mut self,deadline:Instant)->io::Result<String> {
        let mut scanned=0;
        loop {
            if Instant::now()>=deadline{return Err(io::Error::new(io::ErrorKind::TimedOut,"OBS control deadline exceeded"));}
            if let Some(offset)=self.pending[scanned..].iter().position(|b|*b==b'\n') {
                let end=scanned+offset;
                let bytes:Vec<u8>=self.pending.drain(..=end).collect();
                return String::from_utf8(bytes).map_err(|_|err("invalid OBS response encoding"));
            }
            scanned=self.pending.len();
            if self.pending.len()==LIMIT{return Err(err("oversized OBS response"));}
            poll_until(&mut [PollFd{fd:self.reader.as_raw_fd(),events:POLLIN,revents:0}],deadline)?;
            let mut chunk=[0u8;8192];
            let size=chunk.len().min(LIMIT-self.pending.len());
            match self.reader.read(&mut chunk[..size]) {
                Ok(0)=>return Err(err("OBS websocket closed")),
                Ok(n)=>self.pending.extend_from_slice(&chunk[..n]),
                Err(e) if matches!(e.kind(),io::ErrorKind::WouldBlock|io::ErrorKind::Interrupted)=>{},
                Err(e)=>return Err(e),
            }
        }
    }
}

fn run_bounded(program:&str,args:&[&str],input:&[u8],cap:usize,deadline:Instant)->io::Result<Vec<u8>> {
    if input.len()>LIMIT{return Err(err("oversized OBS helper input"));}
    let mut child=Command::new(program).args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    let result=(|| {
        let stdin=child.stdin.take().ok_or_else(||err("helper stdin unavailable"))?;
        let mut stdout=child.stdout.take().ok_or_else(||err("helper stdout unavailable"))?;
        nonblocking(stdin.as_raw_fd())?;nonblocking(stdout.as_raw_fd())?;
        let mut input=input;
        let mut writer=Some(stdin);
        let mut output=Vec::new();
        let mut eof=false;
        loop {
            if input.is_empty(){writer.take();}
            let mut fds=[PollFd{fd:writer.as_ref().map_or(-1,AsRawFd::as_raw_fd),events:POLLOUT,revents:0},PollFd{fd:if eof{-1}else{stdout.as_raw_fd()},events:POLLIN,revents:0}];
            // A helper may close stdout and continue running. Keep its exit under the same deadline.
            if eof&&writer.is_none() {
                if let Some(status)=child.try_wait()? {
                    return if status.success(){Ok(output)}else{Err(err("OBS helper failed"))};
                }
                let tick=(Instant::now()+Duration::from_millis(10)).min(deadline);
                match poll_until(&mut fds,tick){Ok(())=>{},Err(e) if e.kind()==io::ErrorKind::TimedOut&&Instant::now()<deadline=>{},Err(e)=>return Err(e)}
                continue;
            }
            poll_until(&mut fds,deadline)?;
            if fds[0].revents!=0 {
                match writer.as_mut().unwrap().write(input) {
                    Ok(0)=>return Err(err("OBS helper stdin closed")),
                    Ok(n)=>input=&input[n..],
                    Err(e) if matches!(e.kind(),io::ErrorKind::WouldBlock|io::ErrorKind::Interrupted)=>{},
                    Err(e)=>return Err(e),
                }
            }
            if fds[1].revents!=0 {
                let mut chunk=[0u8;8192];
                let size=chunk.len().min(cap.saturating_sub(output.len()).saturating_add(1));
                match stdout.read(&mut chunk[..size]) {
                    Ok(0)=>eof=true,
                    Ok(n)=>{if n>cap-output.len(){return Err(err("oversized OBS helper output"));}output.extend_from_slice(&chunk[..n]);},
                    Err(e) if matches!(e.kind(),io::ErrorKind::WouldBlock|io::ErrorKind::Interrupted)=>{},
                    Err(e)=>return Err(e),
                }
            }
        }
    })();
    if result.is_err(){let _=child.kill();}
    let _=child.wait();
    result
}

fn err(msg:&str)->io::Error{io::Error::new(io::ErrorKind::Other,msg)}
fn json_lookup(payload:&str,filter:&str)->io::Result<String>{
    json_at(payload,filter,Instant::now()+TIMEOUT)
}
fn json_at(payload:&str,filter:&str,deadline:Instant)->io::Result<String>{
    let filter=format!("if length==1 then .[0] else error(\"one value required\") end | ({filter})");
    let bytes=run_bounded("jq",&["-rsc",&filter],payload.as_bytes(),LIMIT,deadline)?;
    let out=String::from_utf8(bytes).map_err(|_|err("invalid OBS JSON encoding"))?;
    Ok(out.strip_suffix('\n').unwrap_or(&out).to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use std::time::Instant;

    #[test]
    fn stalled_obs_response_is_bounded() {
        let mut child=Command::new("sh").args(["-c","printf partial; exec sleep 30"])
            .stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
        let input=child.stdin.take().unwrap();
        let output=Lines::new(child.stdout.take().unwrap()).unwrap();
        let mut obs=Obs{child,input,output,seq:0};
        let started=Instant::now();
        assert!(obs.next(Instant::now()+TIMEOUT).is_err());
        assert!(started.elapsed()<Duration::from_secs(6));
    }

    #[test]
    fn events_do_not_extend_transaction_deadline() {
        let mut child=Command::new("sh").args(["-c","sleep 2; printf '%s\n' '{\"op\":5}'; exec sleep 30"])
            .stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
        let input=child.stdin.take().unwrap();nonblocking(input.as_raw_fd()).unwrap();
        let output=Lines::new(child.stdout.take().unwrap()).unwrap();
        let mut obs=Obs{child,input,output,seq:0};
        let started=Instant::now();
        assert_eq!(obs.call("GetVersion","{}").unwrap_err().kind(),io::ErrorKind::TimedOut);
        assert!(started.elapsed()<Duration::from_secs(6));
    }

    #[test]
    fn atomic_state_does_not_follow_temp_symlink() {
        let dir=std::env::temp_dir().join(format!("splitcast-obs-red-{}",std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let victim=dir.join("victim");
        fs::write(&victim,"untouched").unwrap();
        let state=dir.join("state.json");
        symlink(&victim,state.with_extension("tmp")).unwrap();
        let result=atomic_file(&state,"private");
        assert_eq!(fs::read_to_string(&victim).unwrap(),"untouched");
        result.unwrap();
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn partial_bytes_do_not_extend_deadline() {
        let (reader,mut writer)=std::os::unix::net::UnixStream::pair().unwrap();
        let thread=std::thread::spawn(move||{
            for _ in 0..100 {
                if writer.write_all(b"x").is_err(){break;}
                std::thread::sleep(Duration::from_millis(10));
            }
        });
        let mut lines=Lines::new(reader).unwrap();
        let start=Instant::now();
        assert_eq!(lines.next(start+Duration::from_millis(100)).unwrap_err().kind(),io::ErrorKind::TimedOut);
        assert!(start.elapsed()<Duration::from_millis(500));
        drop(lines);thread.join().unwrap();
    }

    #[test]
    fn oversized_unterminated_response_is_rejected() {
        let (reader,mut writer)=std::os::unix::net::UnixStream::pair().unwrap();
        let thread=std::thread::spawn(move||{let _=writer.write_all(&vec![b'x';LIMIT+1]);});
        let mut lines=Lines::new(reader).unwrap();
        assert!(lines.next(Instant::now()+TIMEOUT).unwrap_err().to_string().contains("oversized"));
        assert!(lines.pending.len()<=LIMIT);
        drop(lines);thread.join().unwrap();
    }

    #[test]
    fn blocked_writes_and_helpers_are_bounded() {
        let (mut writer,_reader)=std::os::unix::net::UnixStream::pair().unwrap();
        nonblocking(writer.as_raw_fd()).unwrap();
        assert_eq!(write_until(&mut writer,&vec![0;LIMIT],Instant::now()+Duration::from_millis(100)).unwrap_err().kind(),io::ErrorKind::TimedOut);
        assert_eq!(run_bounded("sh",&["-c","exec sleep 30"],b"",100,Instant::now()+Duration::from_millis(100)).unwrap_err().kind(),io::ErrorKind::TimedOut);
        assert!(run_bounded("sh",&["-c","exec yes x"],b"",100,Instant::now()+TIMEOUT).unwrap_err().to_string().contains("oversized"));
    }

    #[test]
    fn state_paths_reject_symlinks_and_keep_private_modes() {
        let dir=std::env::temp_dir().join(format!("splitcast-obs-state-{}",std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let victim=dir.join("victim");fs::write(&victim,"untouched").unwrap();
        let state=dir.join("state");symlink(&victim,&state).unwrap();
        assert!(atomic_file(&state,"private").is_err());
        assert_eq!(fs::read_to_string(&victim).unwrap(),"untouched");
        fs::remove_file(&state).unwrap();
        atomic_file(&state,"private").unwrap();
        assert_eq!(fs::metadata(&state).unwrap().mode()&0o777,0o600);
        assert_eq!(fs::metadata(&dir).unwrap().mode()&0o777,0o700);
        let alias=dir.join("alias");symlink(&dir,&alias).unwrap();
        assert!(atomic_file(&alias.join("other"),"private").is_err());
        fs::remove_dir_all(dir).unwrap();
    }

    fn config(dir:&std::path::Path,port:u16)->Config {
        Config{
            role:"production".into(),state_dir:dir.into(),token_file:dir.join("token"),remote_token_file:dir.join("token"),
            ssh_host:"localhost".into(),ssh_port:22,control_port:18001,remote_control_port:18002,forward_control_port:18003,timeout:1,retry_limit:0,
            rtmp:18004,rtsp:18005,api:18006,width:1920,height:1080,fps:60,bitrate:10000,target:String::new(),game_audio:String::new(),
            mic_source:String::new(),tts_sink:String::new(),processed_sink:"splitcast_mic".into(),rnnoise_plugin:dir.join("rnnoise"),
            rnnoise_label:String::new(),rnnoise_control:String::new(),gain_db:0,mic_offset:0,camera_enabled:false,camera_location:"production".into(),
            camera_mode:"h264".into(),camera_device:String::new(),camera_encoder:"h264_nvenc".into(),camera_hw:dir.into(),camera_width:640,camera_height:480,camera_fps:30,
            obs_binary:"obs".into(),obs_port:port,obs_password:dir.join("password"),twitch_key:dir.join("twitch"),recording_dir:dir.join("recordings"),
            tts_enabled:false,voicevox_url:String::new(),tts_speaker:0,tts_max_text:100,tts_queue_limit:1,tts_expiry_seconds:5,tts_credentials_file:dir.join("tts"),tts_mix_remote:false,eventsub_enabled:false,
        }
    }

    #[test]
    fn launch_refuses_occupied_port() {
        let dir=std::env::temp_dir().join(format!("splitcast-obs-launch-{}",std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let listener=TcpListener::bind((Ipv4Addr::LOCALHOST,0)).unwrap();
        let cfg=config(&dir,listener.local_addr().unwrap().port());
        fs::write(&cfg.obs_password,"a-private-password-long-enough").unwrap();
        fs::set_permissions(&cfg.obs_password,fs::Permissions::from_mode(0o600)).unwrap();
        assert!(launch_args(&cfg).unwrap_err().to_string().contains("occupied"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn launch_refuses_public_credentials() {
        let dir=std::env::temp_dir().join(format!("splitcast-obs-credentials-{}",std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        // Avoid ephemeral ports that the concurrent websocat test can claim after this listener closes.
        let listener=(20000..30000).find_map(|port|TcpListener::bind((Ipv4Addr::LOCALHOST,port)).ok()).unwrap();
        let cfg=config(&dir,listener.local_addr().unwrap().port());
        drop(listener);
        fs::write(&cfg.obs_password,"a-private-password-long-enough").unwrap();
        fs::set_permissions(&cfg.obs_password,fs::Permissions::from_mode(0o644)).unwrap();
        assert!(launch_args(&cfg).is_err());
        fs::set_permissions(&cfg.obs_password,fs::Permissions::from_mode(0o600)).unwrap();
        launch_args(&cfg).unwrap();
        assert_eq!(fs::metadata(&cfg.obs_password).unwrap().mode()&0o777,0o600);
        assert_eq!(fs::read_to_string(&cfg.obs_password).unwrap(),"a-private-password-long-enough");
        fs::remove_dir_all(dir).unwrap();
    }

    fn websocket_frame(stream:&mut TcpStream,text:&str) {
        let size=text.len();
        assert!(size<65536);
        let header=if size<126 {vec![0x81,size as u8]}else{vec![0x81,126,(size>>8) as u8,size as u8]};
        stream.write_all(&header).unwrap();stream.write_all(text.as_bytes()).unwrap();
    }
    fn websocket_read(stream:&mut TcpStream)->String {
        let mut header=[0;2];stream.read_exact(&mut header).unwrap();
        assert_eq!(header[0],0x81);assert_ne!(header[1]&128,0);
        let mut size=(header[1]&127) as usize;
        if size==126 {let mut extended=[0;2];stream.read_exact(&mut extended).unwrap();size=u16::from_be_bytes(extended) as usize;}
        assert!(size<65536);
        let mut mask=[0;4];stream.read_exact(&mut mask).unwrap();
        let mut data=vec![0;size];stream.read_exact(&mut data).unwrap();
        for (index,byte) in data.iter_mut().enumerate(){*byte^=mask[index%4];}
        String::from_utf8(data).unwrap()
    }

    #[test]
    fn authenticates_and_decodes_preview_over_real_websocket() {
        let dir=std::env::temp_dir().join(format!("splitcast-obs-websocket-{}",std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let listener=TcpListener::bind((Ipv4Addr::LOCALHOST,0)).unwrap();
        let cfg=config(&dir,listener.local_addr().unwrap().port());
        fs::write(&cfg.obs_password,"a-private-password-long-enough").unwrap();
        fs::set_permissions(&cfg.obs_password,fs::Permissions::from_mode(0o600)).unwrap();
        let server=std::thread::spawn(move|| {
            // connect() first probes the TCP port, then websocat performs the upgrade.
            let (probe,_)=listener.accept().unwrap();drop(probe);
            let (mut stream,_)=listener.accept().unwrap();
            stream.set_read_timeout(Some(TIMEOUT)).unwrap();stream.set_write_timeout(Some(TIMEOUT)).unwrap();
            let mut header=Vec::new();
            while !header.ends_with(b"\r\n\r\n") {
                let mut byte=[0];stream.read_exact(&mut byte).unwrap();header.push(byte[0]);assert!(header.len()<8192);
            }
            let header=String::from_utf8(header).unwrap();
            let key=header.lines().find_map(|line|line.split_once(':').filter(|(name,_)|name.eq_ignore_ascii_case("sec-websocket-key")).map(|(_,value)|value.trim())).unwrap();
            let accept=run_bounded("websocat",&["--just-generate-accept",key],b"",256,Instant::now()+TIMEOUT).unwrap();
            write!(stream,"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {}\r\n\r\n",String::from_utf8(accept).unwrap().trim()).unwrap();
            websocket_frame(&mut stream,r#"{"op":0,"d":{"authentication":{"salt":"salt\u0022","challenge":"challenge\\"}}}"#);
            let identify=websocket_read(&mut stream);
            let secret=base64_sha(b"a-private-password-long-enoughsalt\"",Instant::now()+TIMEOUT).unwrap();
            let proof=base64_sha(format!("{secret}challenge\\").as_bytes(),Instant::now()+TIMEOUT).unwrap();
            assert_eq!(json_lookup(&identify,".d.authentication").unwrap(),proof);
            websocket_frame(&mut stream,"{\"op\":2}");
            let request=websocket_read(&mut stream);
            assert_eq!(json_lookup(&request,".d.requestType").unwrap(),"GetSourceScreenshot");
            websocket_frame(&mut stream,r#"{"op":7,"d":{"requestId":"1","requestStatus":{"result":true},"responseData":{"imageData":"data:image\/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8\/x8AAwMCAO+a8xkAAAAASUVORK5CYII="}}}"#);
        });
        let mut obs=Obs::connect(&cfg).unwrap();
        let preview=obs.preview().unwrap();
        assert!(preview.starts_with("{\"image\":\"data:image/png;base64,iVBORw0KGgo"));
        server.join().unwrap();drop(obs);fs::remove_dir_all(dir).unwrap();
    }
}
fn base64_sha(input:&[u8],deadline:Instant)->io::Result<String>{
    let digest=run_bounded("openssl",&["dgst","-sha256","-binary"],input,32,deadline)?;
    if digest.len()!=32{return Err(err("openssl SHA256 failed"));}
    let bytes=run_bounded("base64",&["-w0"],&digest,44,deadline)?;
    String::from_utf8(bytes).map_err(|_|err("invalid base64 output"))
}
pub struct Obs {
    child: Child,
    input: ChildStdin,
    output: Lines<ChildStdout>,
    seq:u64,
}
impl Obs {
    pub fn connect(cfg:&Config)->io::Result<Self>{
        let deadline=Instant::now()+TIMEOUT;
        // Never connect to a LAN/tailnet OBS WebSocket. SSH forwarding happens
        // only for the control agent; OBS is bound to 127.0.0.1.
        let addr=SocketAddrV4::new(Ipv4Addr::LOCALHOST,cfg.obs_port);
        TcpStream::connect_timeout(&addr.into(),Duration::from_secs(2))?;
        let mut child=Command::new("websocat")
            .args(["-t","-B","4194304","--max-ws-frame-length","4194304","--max-ws-message-length","4194304"])
            .arg(format!("ws://127.0.0.1:{}",cfg.obs_port))
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
        let input=child.stdin.take().ok_or_else(||err("OBS websocket stdin unavailable"))?;
        let stdout=child.stdout.take().ok_or_else(||err("OBS websocket stdout unavailable"))?;
        let output=match Lines::new(stdout).and_then(|out|{nonblocking(input.as_raw_fd())?;Ok(out)}) {
            Ok(out)=>out,Err(e)=>{let _=child.kill();let _=child.wait();return Err(e);}
        };
        let mut obs=Self{child,input,output,seq:0};
        let hello=obs.next(deadline)?;
        if json_at(&hello,".op",deadline)?!="0" {return Err(err("OBS WebSocket v5 Hello required"));}
        let string_filter="if type==\"string\" and length>0 and length<=4096 then . else error(\"authentication string required\") end";
        let salt=json_at(&hello,&format!(".d.authentication.salt | {string_filter}"),deadline)?;
        let challenge=json_at(&hello,&format!(".d.authentication.challenge | {string_filter}"),deadline)?;
        let password=secret(&cfg.obs_password,4096)?;
        if password.len()<16{return Err(err("OBS password is missing or too short"));}
        let secret=base64_sha(format!("{password}{salt}").as_bytes(),deadline)?;
        let proof=base64_sha(format!("{secret}{challenge}").as_bytes(),deadline)?;
        obs.send(&format!("{{\"op\":1,\"d\":{{\"rpcVersion\":1,\"authentication\":{}}}}}",json_string(&proof)),deadline)?;
        if json_at(&obs.next(deadline)?,".op",deadline)?!="2" {return Err(err("OBS WebSocket authentication rejected"));}
        Ok(obs)
    }
    fn send(&mut self,text:&str,deadline:Instant)->io::Result<()>{
        if text.len()>LIMIT{return Err(err("oversized OBS request"));}
        write_until(&mut self.input,text.as_bytes(),deadline)?;
        write_until(&mut self.input,b"\n",deadline)
    }
    fn next(&mut self,deadline:Instant)->io::Result<String>{
        self.output.next(deadline)
    }
    pub fn call(&mut self,name:&str,body:&str)->io::Result<String>{
        let deadline=Instant::now()+TIMEOUT;
        if body.len()>LIMIT/2 || name.len()>256{return Err(err("oversized OBS request"));}
        self.seq+=1;let id=self.seq.to_string();
        let request=format!("{{\"op\":6,\"d\":{{\"requestType\":{},\"requestId\":{},\"requestData\":{}}}}}",json_string(name),json_string(&id),body);
        self.send(&request,deadline)?;
        for _ in 0..64 {
            let answer=self.next(deadline)?;
            if json_at(&answer,".op",deadline)?!="7"{continue;}
            if json_at(&answer,".d.requestId",deadline)?!=id{continue;}
            if json_at(&answer,".d.requestStatus.result",deadline)?!="true"{return Err(err("OBS request rejected"));}
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
        let key=secret(&cfg.twitch_key,4096)?;
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
    pub fn preview(&mut self)->io::Result<String>{
        let ret=self.call("GetSourceScreenshot","{\"sourceName\":\"SplitCast\",\"imageFormat\":\"png\",\"imageWidth\":960,\"imageHeight\":540}")?;
        let image=json_lookup(&ret,".d.responseData.imageData | if type==\"string\" then . else error(\"image required\") end")?;
        let data=image.strip_prefix("data:image/png;base64,").ok_or_else(||err("invalid OBS preview format"))?;
        if data.len()<12 || data.len()%4!=0 || !data.starts_with("iVBORw0KGgo") ||
            !data.trim_end_matches('=').bytes().all(|b|b.is_ascii_alphanumeric()||b"+/".contains(&b)) ||
            data.len()-data.trim_end_matches('=').len()>2 {
            return Err(err("invalid OBS preview PNG data"));
        }
        Ok(format!("{{\"image\":{}}}",json_string(&image)))
    }
}
impl Drop for Obs {fn drop(&mut self){let _=self.child.kill();let _=self.child.wait();}}

fn atomic_file(p:&std::path::Path,s:&str)->io::Result<()> {
    let dir=p.parent().ok_or_else(||err("invalid state path"))?;
    let directory=private_directory(dir)?;
    let anchored=std::path::PathBuf::from(format!("/proc/self/fd/{}",directory.as_raw_fd()));
    let target=anchored.join(p.file_name().ok_or_else(||err("invalid state filename"))?);
    match fs::symlink_metadata(&target) {
        Ok(m) if !m.is_file()=>return Err(err("state target must be a regular file")),
        Ok(_)=>{},Err(e) if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e),
    }
    static NEXT:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(0);
    let stamp=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|_|err("invalid system clock"))?.as_nanos();
    let part=anchored.join(format!(".splitcast-{}-{stamp}-{}.tmp",std::process::id(),NEXT.fetch_add(1,std::sync::atomic::Ordering::Relaxed)));
    let mut file=fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&part)?;
    let result=(||{file.write_all(s.as_bytes())?;file.sync_all()?;fs::rename(&part,&target)?;directory.sync_all()})();
    if result.is_err(){let _=fs::remove_file(&part);}
    result
}
fn private_directory(path:&std::path::Path)->io::Result<fs::File>{
    use std::path::Component;
    let path=if path.is_absolute(){path.to_owned()}else{std::env::current_dir()?.join(path)};
    let mut current=fs::File::open("/")?;
    for component in path.components() {
        let name=match component {Component::RootDir|Component::CurDir=>continue,Component::Normal(name)=>name,_=>return Err(err("invalid state directory"))};
        // Resolve through pinned directory descriptors, never through a symlink in the state path.
        let next=std::path::PathBuf::from(format!("/proc/self/fd/{}",current.as_raw_fd())).join(name);
        match fs::DirBuilder::new().mode(0o700).create(&next) {
            Ok(())=>{},Err(e) if e.kind()==io::ErrorKind::AlreadyExists=>{},Err(e)=>return Err(e),
        }
        current=fs::OpenOptions::new().read(true).custom_flags(O_DIRECTORY|O_NOFOLLOW).open(&next)?;
    }
    unsafe extern "C" {fn getuid()->u32;}
    if current.metadata()?.uid()!=unsafe{getuid()}{return Err(err("state directory must belong to this user"));}
    current.set_permissions(fs::Permissions::from_mode(0o700))?;
    Ok(current)
}
pub fn launch_args(cfg:&Config)->io::Result<Vec<String>>{
    let _port=TcpListener::bind((Ipv4Addr::LOCALHOST,cfg.obs_port)).map_err(|_|err("OBS port is already occupied"))?;
    // A dedicated profile avoids contaminating the user's OBS installation.
    let base=cfg.state_dir.join("obs-config");let studio=base.join("obs-studio");
    let password=secret(&cfg.obs_password,4096)?;
    if password.len()<16 {return Err(err("OBS auth password must be at least 16 characters"));}
    for dir in [cfg.state_dir.clone(),base.clone(),studio.clone(),studio.join("plugin_config"),studio.join("basic"),studio.join("basic/profiles")] {
        private_directory(&dir)?;
    }
    atomic_file(&studio.join("plugin_config/obs-websocket/config.json"),&format!("{{\"server_enabled\":true,\"server_port\":{},\"auth_required\":true,\"server_password\":{},\"first_load\":false}}",cfg.obs_port,json_string(&password)))?;
    fs::create_dir_all(&cfg.recording_dir)?;
    let profile=format!("[General]\nName=SplitCast\n[Video]\nBaseCX=1920\nBaseCY=1080\nOutputCX=1920\nOutputCY=1080\nFPSType=0\nFPSCommon=60\n[Output]\nMode=Advanced\n[AdvOut]\nEncoder=obs_nvenc_h264_tex\nRecType=Standard\nRecFilePath={}\nRecFormat2=mkv\nRecEncoder=obs_nvenc_h264_tex\nTrackIndex=1\nRecTracks=1\nRescale=false\n[Audio]\nSampleRate=48000\nChannelSetup=Stereo\n",cfg.recording_dir.display());
    atomic_file(&studio.join("basic/profiles/SplitCast/basic.ini"),&profile)?;
    atomic_file(&studio.join("user.ini"),"[Basic]\nProfile=SplitCast\nProfileDir=SplitCast\nSceneCollection=SplitCast\nSceneCollectionFile=SplitCast\n[General]\nFirstRun=true\n")?;
    atomic_file(&studio.join("basic/scenes/SplitCast.json"),"{\"name\":\"SplitCast\",\"current_scene\":\"SplitCast\",\"current_program_scene\":\"SplitCast\",\"scene_order\":[{\"name\":\"SplitCast\"}],\"sources\":[],\"groups\":[],\"transitions\":[]}")?;
    // The OBS process must be a child owned by the systemd user service.
    Ok(vec!["env".into(),format!("XDG_CONFIG_HOME={}",base.display()),cfg.obs_binary.to_string_lossy().to_string(),"--multi".into(),"--disable-shutdown-check".into(),"--profile".into(),"SplitCast".into(),"--collection".into(),"SplitCast".into()])
}
