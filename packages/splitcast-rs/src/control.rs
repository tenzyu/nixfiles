//! Loopback-only authenticated HTTP boundary; no browser access from LAN.
//! The agent's business logic runs only on the server thread, so its state
//! cannot be mutated concurrently with lifecycle transitions.
use crate::config::{json_string,Config};
use std::io::{self,Read,Write};
use std::net::{Ipv4Addr,SocketAddrV4,TcpListener,TcpStream};
use std::time::Duration;

fn err(msg:&str)->io::Error{io::Error::new(io::ErrorKind::PermissionDenied,msg)}
fn same(a:&str,b:&str)->bool{
    let x=a.as_bytes();let y=b.as_bytes();
    let mut diff=x.len()^y.len();for i in 0..x.len().max(y.len()) {diff|=(x.get(i).copied().unwrap_or(0)^y.get(i).copied().unwrap_or(0)) as usize;}
    diff==0
}
#[derive(Debug)]pub struct Request{pub method:String,pub path:String,pub body:String}
fn header<'a>(headers:&'a [(String,String)],name:&str)->Option<&'a str>{
    let mut it=headers.iter().filter(|(k,_)|k.eq_ignore_ascii_case(name));
    let first=it.next()?.1.as_str();if it.next().is_some(){return None} Some(first)
}
pub fn recv(stream:&mut TcpStream,port:u16,token:&str)->io::Result<Request>{
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    let mut packet=Vec::<u8>::with_capacity(4096);
    let (head,end)=loop {
        if packet.len()>20*1024{return Err(err("HTTP headers oversized"));}
        let mut one=[0u8;1024];let n=stream.read(&mut one)?;
        if n==0{return Err(err("premature EOF"));}
        packet.extend_from_slice(&one[..n]);
        if let Some(idx)=packet.windows(4).position(|x|x==b"\r\n\r\n") {break (idx,idx+4)}
    };
    let header_string=std::str::from_utf8(&packet[..head]).map_err(|_|err("invalid HTTP headers"))?;
    let mut lines=header_string.split("\r\n");
    let first=lines.next().ok_or_else(||err("invalid HTTP request"))?;
    let parts=first.split_ascii_whitespace().collect::<Vec<_>>();
    if parts.len()!=3||parts[2]!="HTTP/1.1"{return Err(err("HTTP/1.1 required"));}
    let mut headers=Vec::new();
    for l in lines {let (k,v)=l.split_once(':').ok_or_else(||err("bad HTTP header"))?;headers.push((k.trim().to_ascii_lowercase(),v.trim().to_string()));}
    let host=header(&headers,"host").ok_or_else(||err("Host required exactly once"))?;
    if host!=format!("127.0.0.1:{port}") && host!=format!("localhost:{port}"){return Err(err("loopback Host required"));}
    let origin=header(&headers,"origin").ok_or_else(||err("same-origin request required"))?;
    if origin!=format!("http://{host}"){return Err(err("same-origin mismatch"));}
    let bearer=header(&headers,"authorization").ok_or_else(||err("bearer token required"))?;
    if !same(bearer,&format!("Bearer {token}")){return Err(err("invalid bearer token"));}
    if header(&headers,"transfer-encoding").is_some(){return Err(err("chunked requests forbidden"));}
    let count=if parts[0]=="POST"{
        if header(&headers,"content-type")!=Some("application/json"){return Err(err("JSON required"));}
        let n=header(&headers,"content-length").ok_or_else(||err("Content-Length required"))?.parse::<usize>().map_err(|_|err("bad length"))?;
        if n==0||n>16384{return Err(err("body exceeds 16KiB"));}n
    }else{0};
    let mut body=packet[end..].to_vec();
    if body.len()>count{return Err(err("HTTP body/length mismatch"));}
    while body.len()<count{
        let mut tmp=[0u8;4096];let remain=(count-body.len()).min(tmp.len());let n=stream.read(&mut tmp[..remain])?;
        if n==0{return Err(err("short HTTP body"));}body.extend_from_slice(&tmp[..n]);
    }
    Ok(Request{method:parts[0].into(),path:parts[1].into(),body:String::from_utf8(body).map_err(|_|err("invalid UTF-8 body"))?})
}
pub fn reply(stream:&mut TcpStream,status:u16,json:&str)->io::Result<()> {
    let reason=if status==200{"OK"}else if status==403{"Forbidden"}else if status==404{"Not Found"}else{"Conflict"};
    write!(stream,"HTTP/1.1 {status} {reason}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; frame-ancestors 'none'\r\n\r\n{}",json.as_bytes().len(),json)?;
    stream.flush()
}
pub fn listener(cfg:&Config)->io::Result<TcpListener>{
    let sock=SocketAddrV4::new(Ipv4Addr::LOCALHOST,cfg.control_port);
    let l=TcpListener::bind(sock)?;l.set_nonblocking(true)?;Ok(l)
}
pub fn request_peer(cfg:&Config,command:&str,args:&str)->io::Result<String>{
    // SSH local forwarding has a different socket port from the Host header.
    // The remote server authenticates its own loopback Host/Origin.
    let mut stream=TcpStream::connect_timeout(&SocketAddrV4::new(Ipv4Addr::LOCALHOST,cfg.forward_control_port).into(),Duration::from_secs(cfg.timeout as u64))?;
    stream.set_read_timeout(Some(Duration::from_secs(cfg.timeout as u64)))?;
    let token=cfg.token(true)?;
    let body=format!("{{\"command\":{},\"args\":{}}}",json_string(command),args);
    let host=format!("127.0.0.1:{}",cfg.remote_control_port);
    write!(stream,"POST /api/command HTTP/1.1\r\nHost: {host}\r\nOrigin: http://{host}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",body.len(),body)?;
    stream.flush()?;
    let mut response=String::new();stream.take(4*1024*1024).read_to_string(&mut response)?;
    let (head,body)=response.split_once("\r\n\r\n").ok_or_else(||err("invalid peer HTTP response"))?;
    if !head.contains(" 200 "){return Err(err("remote SplitCast command rejected"));}
    Ok(body.to_string())
}

#[cfg(test)] mod tests {
    use super::*;
    #[test]fn compare_tokens_length_safe(){assert!(same("Bearer secret","Bearer secret"));assert!(!same("Bearer secret","Bearer secretx"));}
}
