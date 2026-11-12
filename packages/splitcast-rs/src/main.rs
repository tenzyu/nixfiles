//! Native Rust SplitCast control-plane candidate. No Python subprocesses or
//! dependency on osu! code. The production cutover remains explicitly gated
//! until existing negative/media/OBS/TTS/EventSub tests pass on both hosts.
use splitcast_rs_core::{Lifecycle,Output,OwnedProcess,Role,Session};
use splitcast_rs_core::{config,control,media,obs};
use std::collections::BTreeMap;
use std::fs;
use std::io::{self,Read,Write};
use std::net::TcpStream;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path,PathBuf};
use std::process::{Command,ExitCode,Stdio};
use std::thread;
use std::time::{Duration,Instant};

fn err(s:&str)->io::Error{io::Error::new(io::ErrorKind::Other,s)}
fn json_state(s:Lifecycle)->&'static str{
    match s {Lifecycle::Idle=>"idle",Lifecycle::Preparing=>"preparing",Lifecycle::Ready=>"ready",Lifecycle::Running=>"running",Lifecycle::Degraded=>"degraded",Lifecycle::Stopping=>"stopping",Lifecycle::Failed=>"failed"}
}
fn json_lookup(body:&str,filter:&str)->io::Result<String>{
    let mut child=Command::new("jq").args(["-erc",filter]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    child.stdin.take().unwrap().write_all(body.as_bytes())?;
    let out=child.wait_with_output()?;
    if !out.status.success(){return Err(err("invalid JSON command"));}
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
fn rand_hex()->io::Result<String>{
    let mut bytes=[0u8;16];
    let mut f=fs::File::open("/dev/urandom")?;f.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|x|format!("{x:02x}")).collect::<String>())
}
struct Agent {
    cfg:config::Config,
    session:Session,
    children:BTreeMap<String,OwnedProcess>,
    owned_module:Option<u32>,
    owner:String,
    lease:Option<(String,Instant)>,
    output:Option<String>,
    error:String,
    warnings:Vec<String>,
    mic_muted:bool,
}
impl Agent {
    fn new(cfg:config::Config)->io::Result<Self>{
        let role=if cfg.role=="capture"{Role::Capture}else{Role::Production};
        fs::create_dir_all(&cfg.state_dir)?;
        fs::set_permissions(&cfg.state_dir,fs::Permissions::from_mode(0o700))?;
        Ok(Self{cfg,session:Session::new(role),children:BTreeMap::new(),owned_module:None,owner:rand_hex()?,lease:None,output:None,error:String::new(),warnings:vec![],mic_muted:false})
    }
    fn status(&self)->String {
        let list=self.children.keys().map(|k|config::json_string(k)).collect::<Vec<_>>().join(",");
        let notices=self.warnings.iter().map(|x|config::json_string(x)).collect::<Vec<_>>().join(",");
        let out=self.output.as_ref().map(|x|config::json_string(x)).unwrap_or_else(||"null".into());
        format!("{{\"version\":1,\"engine\":\"rust-candidate\",\"role\":{},\"state\":{},\"output\":{out},\"error\":{},\"warnings\":[{notices}],\"mic_muted\":{},\"children\":[{list}]}}",config::json_string(&self.cfg.role),config::json_string(json_state(self.session.state())),config::json_string(&self.error),self.mic_muted)
    }
    fn spawn(&mut self,name:&str,argv:Vec<String>)->io::Result<()> {
        if self.children.contains_key(name){return Err(err("child already owned"));}
        let child=OwnedProcess::spawn(&argv)?;
        self.children.insert(name.into(),child);Ok(())
    }
    fn wait_ready<F>(&self,mut check:F)->io::Result<()> where F:FnMut()->bool {
        let end=Instant::now()+Duration::from_secs(self.cfg.timeout as u64);
        while Instant::now()<end {if check(){return Ok(())}thread::sleep(Duration::from_millis(200));}
        Err(err("external service readiness timeout"))
    }
    fn guard_lease(&self,owner:Option<&str>)->io::Result<()> {
        if let Some((held,_))=&self.lease {
            if Some(held.as_str())!=owner {return Err(err("production is owned by another session"));}
        }
        Ok(())
    }
    fn renew_lease(&mut self,owner:&str)->io::Result<()> {
        self.guard_lease(Some(owner))?;
        self.lease=Some((owner.into(),Instant::now()+Duration::from_secs((self.cfg.timeout as u64*8).max(30))));Ok(())
    }
    fn prepare(&mut self,owner:Option<&str>)->io::Result<()> {
        self.guard_lease(owner)?;
        if self.session.state()!=Lifecycle::Idle {return Err(err("stop before preparing another session"));}
        self.session.prepare().map_err(|_|err("invalid prepare transition"))?;
        let outcome=(||->io::Result<()> {
            let missing=media::check_tools(&self.cfg.role)?;
            if !missing.is_empty(){return Err(err("SplitCast required native tools missing"));}
            if self.cfg.role=="capture" {
                self.spawn("ssh",media::tunnel(&self.cfg))?;
                self.wait_ready(||control::request_peer(&self.cfg,"status","{}").is_ok())?;
                control::request_peer(&self.cfg,"prepare",&format!("{{\"_owner\":{}}}",config::json_string(&self.owner)))?;
            } else {
                self.spawn("mediamtx",media::receiver(&self.cfg)?)?;
                self.wait_ready(||media::run("curl",&["-fsS","--max-time","2",&media::pcm_paths(&self.cfg)]).is_ok())?;
                self.owned_module=Some(media::prepare_processed_sink(&self.cfg)?);
                self.spawn("obs",obs::launch_args(&self.cfg)?)?;
                self.wait_ready(||obs::Obs::connect(&self.cfg).is_ok())?;
                let mut o=obs::Obs::connect(&self.cfg)?;
                o.configure(&self.cfg)?;
            }
            Ok(())
        })();
        if let Err(e)=outcome{
            self.error=e.to_string();self.cleanup();let _=self.session.fail();return Err(e)
        }
        self.session.prepared().map_err(|_|err("prepare failed"))?;
        if let Some(o)=owner{self.renew_lease(o)?;}
        Ok(())
    }
    fn start(&mut self,which:&str,owner:Option<&str>)->io::Result<()> {
        if which!="recording"&&which!="twitch"{return Err(err("explicit recording/twitch output required"));}
        self.guard_lease(owner)?;
        if self.session.state()==Lifecycle::Idle {self.prepare(owner)?;}
        if self.session.state()!=Lifecycle::Ready{return Err(err("not prepared"));}
        let outcome=(||->io::Result<()> {
            if self.cfg.role=="capture" {
                self.spawn("game",media::game(&self.cfg)?)?;
                self.spawn("mic",media::mic(&self.cfg)?)?;
                if self.cfg.camera_enabled&&self.cfg.camera_location=="capture"{self.spawn("camera",media::camera(&self.cfg)?)?;}
                control::request_peer(&self.cfg,"start",&format!("{{\"output\":{},\"_owner\":{}}}",config::json_string(which),config::json_string(&self.owner)))?;
            }else {
                if self.cfg.camera_enabled&&self.cfg.camera_location=="production"{self.spawn("camera",media::camera(&self.cfg)?)?;}
                self.spawn("rnnoise",media::rnnoise(&self.cfg)?)?;
                self.wait_ready(|| {
                    if let Ok(v)=media::run("curl",&["-fsS","--max-time","2",&media::pcm_paths(&self.cfg)]){
                        media::ready_output(&v,"game")&&media::ready_output(&v,"mic")
                    }else{false}
                })?;
                let mut o=obs::Obs::connect(&self.cfg)?;
                o.configure(&self.cfg)?;
                o.start(&self.cfg,which)?;
                self.wait_ready(||obs::Obs::connect(&self.cfg).and_then(|mut o|o.status(which)).unwrap_or(false))?;
            }
            Ok(())
        })();
        if let Err(e)=outcome{self.error=e.to_string();self.cleanup();let _=self.session.fail();return Err(e);}
        let target=if which=="recording"{Output::Recording}else{Output::Twitch};
        self.session.start(target).map_err(|_|err("start lifecycle error"))?;
        self.output=Some(which.into());
        if let Some(o)=owner{self.renew_lease(o)?;}
        Ok(())
    }
    fn cleanup(&mut self){
        if self.cfg.role=="production"{
            if let Ok(mut o)=obs::Obs::connect(&self.cfg){let _=o.stop();}
        }
        if self.cfg.role=="capture" && self.children.contains_key("ssh"){
            let _=control::request_peer(&self.cfg,"stop",&format!("{{\"_owner\":{}}}",config::json_string(&self.owner)));
        }
        for name in ["game","mic","camera","rnnoise","obs","mediamtx","ssh"]{
            if let Some(mut ch)=self.children.remove(name){let _=ch.stop(Duration::from_secs(2));}
        }
        if let Some(id)=self.owned_module.take(){let _=media::release_processed_sink(id);}
    }
    fn stop(&mut self,owner:Option<&str>)->io::Result<()> {
        self.guard_lease(owner)?;
        if self.session.state()==Lifecycle::Idle{return Ok(());}
        self.session.stop().map_err(|_|err("stop lifecycle error"))?;
        self.cleanup();
        self.session.stopped().map_err(|_|err("stop completion error"))?;
        self.output=None;self.error.clear();self.lease=None;self.mic_muted=false;Ok(())
    }
    fn tick(&mut self) {
        let expired=self.lease.as_ref().map(|(_,when)| Instant::now()>*when).unwrap_or(false);
        if expired {
            let _=self.session.stop();
            self.cleanup();
            let _=self.session.stopped();
            self.output=None;self.lease=None;
            self.warnings.push("production owner lease expired; all owned media stopped".into());
        }
        if self.session.state()==Lifecycle::Running {
            let mut dead=false;
            for child in self.children.values_mut(){if child.try_wait().ok().flatten().is_some(){dead=true;}}
            if dead {let _=self.session.degrade();self.warnings.push("media process exited; explicit stop required".into());}
        }
    }
    fn command(&mut self,cmd:&str,args:&str)->io::Result<String>{
        let owner=json_lookup(args,"._owner // null")?.trim_matches('"').to_string();
        let owner=if owner=="null" {None}else{Some(owner.as_str())};
        match cmd {
            "status"=>Ok(self.status()),
            "heartbeat"=>{if let Some(o)=owner{self.renew_lease(o)?;}Ok(self.status())},
            "doctor"=>{let missing=media::check_tools(&self.cfg.role)?;Ok(format!("{{\"ok\":{},\"missing\":[{}]}}",missing.is_empty(),missing.iter().map(|x|config::json_string(x)).collect::<Vec<_>>().join(",")))},
            "prepare"=>{self.prepare(owner)?;Ok(self.status())},
            "start"=>{
                let output=json_lookup(args,".output // \"recording\"")?;
                self.start(output.trim_matches('"'),owner)?;Ok(self.status())
            },
            "stop"=>{self.stop(owner)?;Ok(self.status())},
            "devices"=>{let p=media::run("pactl",&["-f","json","list","sources"])?;Ok(format!("{{\"sources\":{}}}",p))},
            "routes"=>Ok("{\"status\":\"read-only; route editing not yet ported\"}".into()),
            "mic"=>{
                if self.cfg.role!="production" {return Err(err("mic controls belong to production"));}
                let action=json_lookup(args,".action // \"status\"")?;
                match action.trim_matches('"') {
                    "mute"=>self.mic_muted=true,"unmute"=>self.mic_muted=false,"status"=>{},_=>return Err(err("invalid mic action"))
                }
                let mut o=obs::Obs::connect(&self.cfg)?;
                o.call("SetInputMute",&format!("{{\"inputName\":\"MicProcessed\",\"inputMuted\":{}}}",self.mic_muted))?;
                Ok(self.status())
            },
            "overlay"=>{
                if self.cfg.role!="production"{return Err(err("overlay belongs to production"));}
                let s=json_lookup(args,".text // empty")?;
                let mut o=obs::Obs::connect(&self.cfg)?;o.overlay(s.trim_matches('"'))?;Ok(self.status())
            },
            "tts"|"say"|"tts-next"|"tts-ack"|"tts-finished"=>Err(err("TTS / EventSub protocol parity not yet implemented; no silent fallback")),
            "preview"=>Err(err("OBS screenshot binary response parity not yet implemented")),
            "diagnostics"=>Ok(self.status()),
            _=>Err(err("unsupported SplitCast command"))
        }
    }
}
impl Drop for Agent{fn drop(&mut self){self.cleanup();}}
fn serve(cfg:config::Config)->io::Result<()> {
    let token=cfg.token(false)?;
    let listener=control::listener(&cfg)?;
    let mut agent=Agent::new(cfg.clone())?;
    eprintln!("SplitCast Rust candidate: loopback control on 127.0.0.1:{}; no automatic streaming",cfg.control_port);
    loop {
        match listener.accept(){
            Ok((mut stream,_))=> {
                let answer=match control::recv(&mut stream,cfg.control_port,&token){
                    Ok(r)=> {
                        let command=if r.method=="GET"&&r.path=="/api/status"{Some(("status".to_string(),"{}".to_string()))}
                            else if r.method=="POST"&&r.path=="/api/command"{
                                let name=json_lookup(&r.body,".command").unwrap_or_default();
                                let args=json_lookup(&r.body,".args").unwrap_or_default();
                                Some((name.trim_matches('"').to_string(),args))
                            }else{None};
                        match command {Some((n,args))=>agent.command(&n,&args).map(|body|(200,body)),None=>Ok((404,"{\"error\":\"unknown endpoint\"}".into()))}
                    },Err(_)=>Ok((403,"{\"error\":\"unauthorized or malformed request\"}".into()))
                };
                let (code,body)=answer.unwrap_or_else(|e|(409,format!("{{\"error\":{}}}",config::json_string(&e.to_string()))));
                let _=control::reply(&mut stream,code,&body);
            },
            Err(ref e) if e.kind()==io::ErrorKind::WouldBlock=>{},
            Err(e)=>return Err(e),
        }
        agent.tick();thread::sleep(Duration::from_millis(50));
    }
}
fn cli(cfg:&config::Config,name:&str,args:&str)->io::Result<String>{
    let mut stream=TcpStream::connect_timeout(&format!("127.0.0.1:{}",cfg.control_port).parse().unwrap(),Duration::from_secs(2))?;
    let token=cfg.token(false)?;
    let host=format!("127.0.0.1:{}",cfg.control_port);
    let body=format!("{{\"command\":{},\"args\":{}}}",config::json_string(name),args);
    write!(stream,"POST /api/command HTTP/1.1\r\nHost: {host}\r\nOrigin: http://{host}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",body.len(),body)?;
    stream.flush()?;
    let mut ret=String::new();stream.take(4*1024*1024).read_to_string(&mut ret)?;
    let (head,body)=ret.split_once("\r\n\r\n").ok_or_else(||err("bad control response"))?;
    if !head.contains(" 200 "){return Err(err("agent rejected command"));}
    Ok(body.into())
}
fn real_main()->io::Result<()> {
    let args:Vec<String>=std::env::args().skip(1).collect();
    if args.first().map(String::as_str)==Some("selfcheck") {
        let mut s=Session::new(Role::Capture);
        s.prepare().unwrap();s.prepared().unwrap();s.stop().unwrap();s.stopped().unwrap();
        println!("splitcast-rs-core: lifecycle selfcheck passed; no media streamed");return Ok(())
    }
    let i=args.iter().position(|x|x=="--config").ok_or_else(||err("usage: splitcast-rs-core --config FILE agent|status|prepare|start|stop|doctor|devices"))?;
    let filename=args.get(i+1).ok_or_else(||err("missing config file"))?;
    let cfg=config::Config::load(Path::new(filename))?;
    let command=args.iter().enumerate().filter(|(j,_)|*j!=i&&*j!=i+1).map(|(_,a)|a.as_str()).collect::<Vec<_>>();
    let cmd=command.first().ok_or_else(||err("missing action"))?;
    if *cmd=="agent"{return serve(cfg)}
    let payload=match *cmd{
        "start"=>{
            let output=command.windows(2).find(|x|x[0]=="--output").map(|x|x[1]).unwrap_or("recording");
            format!("{{\"output\":{}}}",config::json_string(output))
        },
        "mic"|"tts"=>format!("{{\"action\":{}}}",config::json_string(command.get(1).unwrap_or(&"status"))),
        "say"|"overlay"=>format!("{{\"text\":{}}}",config::json_string(command.get(1).ok_or_else(||err("missing text"))?)),
        _=>"{}".into(),
    };
    println!("{}",cli(&cfg,cmd,&payload)?);Ok(())
}
fn main()->ExitCode{match real_main(){Ok(())=>ExitCode::SUCCESS,Err(e)=>{eprintln!("splitcast-rs: {e}");ExitCode::FAILURE}}}
