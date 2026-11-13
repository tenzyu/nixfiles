//! Finite HTTP messages on authenticated loopback connections.
use crate::config::{json_string, Config};
use std::collections::BTreeMap;
use std::io::{self, Read, Write};
use std::net::Shutdown;
use std::net::{Ipv4Addr, SocketAddrV4, TcpListener, TcpStream};
use std::time::{Duration, Instant};

const HEADER_LIMIT: usize = 20 * 1024;
const BODY_LIMIT: usize = 16 * 1024;
const RESPONSE_LIMIT: usize = 4 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);

fn err(msg: &str) -> io::Error {
    io::Error::new(io::ErrorKind::PermissionDenied, msg)
}

fn same(a: &str, b: &str) -> bool {
    let x = a.as_bytes();
    let y = b.as_bytes();
    let mut diff = x.len() ^ y.len();
    for i in 0..x.len().max(y.len()) {
        diff |= (x.get(i).copied().unwrap_or(0) ^ y.get(i).copied().unwrap_or(0)) as usize;
    }
    diff == 0
}

fn remaining(deadline: Instant) -> io::Result<Duration> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|d| !d.is_zero())
        .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "HTTP deadline exceeded"))
}

fn read_until_header(stream: &mut TcpStream, deadline: Instant) -> io::Result<(String, Vec<u8>)> {
    let mut packet = Vec::new();
    loop {
        stream.set_read_timeout(Some(remaining(deadline)?))?;
        let mut buf = [0; 1024];
        let n = stream.read(&mut buf)?;
        if n == 0 {
            return Err(err("premature HTTP EOF"));
        }
        packet.extend_from_slice(&buf[..n]);
        if let Some(end) = packet.windows(4).position(|b| b == b"\r\n\r\n") {
            if end > HEADER_LIMIT {
                return Err(err("HTTP headers oversized"));
            }
            let header = std::str::from_utf8(&packet[..end])
                .map_err(|_| err("invalid HTTP headers"))?
                .to_owned();
            return Ok((header, packet[end + 4..].to_vec()));
        }
        if packet.len() > HEADER_LIMIT {
            return Err(err("HTTP headers oversized"));
        }
    }
}

fn headers<'a>(lines: impl Iterator<Item = &'a str>) -> io::Result<BTreeMap<String, String>> {
    let mut result = BTreeMap::new();
    for line in lines {
        let (key, value) = line
            .split_once(':')
            .ok_or_else(|| err("invalid HTTP header"))?;
        if key.is_empty()
            || !key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || value.bytes().any(|b| b < 32 && b != b'\t' || b == 127)
        {
            return Err(err("invalid HTTP header"));
        }
        if result
            .insert(key.to_ascii_lowercase(), value.trim().to_owned())
            .is_some()
        {
            return Err(err("duplicate HTTP header"));
        }
    }
    if result.contains_key("transfer-encoding") {
        return Err(err("transfer encoding forbidden"));
    }
    Ok(result)
}

fn read_body(
    stream: &mut TcpStream,
    mut body: Vec<u8>,
    count: usize,
    deadline: Instant,
) -> io::Result<Vec<u8>> {
    if body.len() > count {
        return Err(err("HTTP body/length mismatch"));
    }
    while body.len() < count {
        stream.set_read_timeout(Some(remaining(deadline)?))?;
        let mut buf = [0; 4096];
        let size = buf.len().min(count - body.len());
        let n = stream.read(&mut buf[..size])?;
        if n == 0 {
            return Err(err("short HTTP body"));
        }
        body.extend_from_slice(&buf[..n]);
    }
    Ok(body)
}

#[derive(Debug)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub body: String,
}

pub fn recv(stream: &mut TcpStream, port: u16, token: &str) -> io::Result<Request> {
    recv_until(stream, port, token, Instant::now() + REQUEST_TIMEOUT)
}

fn recv_until(
    stream: &mut TcpStream,
    port: u16,
    token: &str,
    deadline: Instant,
) -> io::Result<Request> {
    let (head, body) = read_until_header(stream, deadline)?;
    let mut lines = head.split("\r\n");
    let parts = lines.next().unwrap_or("").split(' ').collect::<Vec<_>>();
    if parts.len() != 3 || parts[2] != "HTTP/1.1" || !matches!(parts[0], "GET" | "POST") {
        return Err(err("finite GET or POST HTTP/1.1 required"));
    }
    let h = headers(lines)?;
    let host = h.get("host").ok_or_else(|| err("Host required"))?;
    if host != &format!("127.0.0.1:{port}") && host != &format!("localhost:{port}") {
        return Err(err("loopback Host required"));
    }
    let origin = format!("http://{host}");
    if h.get("origin").is_some_and(|o| o != &origin) {
        return Err(err("same-origin mismatch"));
    }
    let asset = parts[0] == "GET"
        && matches!(
            parts[1],
            "/" | "/loader.js" | "/splitcast_web.js" | "/splitcast_web_bg.wasm"
        );
    if !asset {
        if h.get("origin") != Some(&origin) {
            return Err(err("same-origin request required"));
        }
        let bearer = h
            .get("authorization")
            .ok_or_else(|| err("bearer token required"))?;
        if !same(bearer, &format!("Bearer {token}")) {
            return Err(err("invalid bearer token"));
        }
    }
    let count = if parts[0] == "POST" {
        if h.get("content-type").map(String::as_str) != Some("application/json") {
            return Err(err("JSON required"));
        }
        let len = h
            .get("content-length")
            .ok_or_else(|| err("Content-Length required"))?;
        if len.is_empty() || !len.bytes().all(|b| b.is_ascii_digit()) {
            return Err(err("invalid Content-Length"));
        }
        let n = len
            .parse::<usize>()
            .map_err(|_| err("invalid Content-Length"))?;
        if n == 0 || n > BODY_LIMIT {
            return Err(err("body exceeds 16KiB"));
        }
        n
    } else {
        if h.get("content-length").is_some_and(|s| s != "0") {
            return Err(err("GET body forbidden"));
        }
        0
    };
    Ok(Request {
        method: parts[0].to_owned(),
        path: parts[1].to_owned(),
        body: String::from_utf8(read_body(stream, body, count, deadline)?)
            .map_err(|_| err("invalid UTF-8 body"))?,
    })
}

pub fn reply_bytes(stream: &mut TcpStream, status: u16, mime: &str, body: &[u8]) -> io::Result<()> {
    stream.set_write_timeout(Some(REQUEST_TIMEOUT))?;
    let reason = match status {
        200 => "OK",
        403 => "Forbidden",
        404 => "Not Found",
        503 => "Service Unavailable",
        _ => "Conflict",
    };
    write!(stream, "HTTP/1.1 {status} {reason}\r\nContent-Type: {mime}\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\n\r\n", body.len())?;
    stream.write_all(body)?;
    stream.flush()
}

pub fn reply(stream: &mut TcpStream, status: u16, json: &str) -> io::Result<()> {
    reply_bytes(
        stream,
        status,
        "application/json; charset=utf-8",
        json.as_bytes(),
    )
}

pub fn reject(stream: &mut TcpStream) -> io::Result<()> {
    reply(
        stream,
        403,
        "{\"error\":\"unauthorized or malformed request\"}",
    )?;
    // RFC 9112 section 9.6. Closing with unread request data can reset the response.
    stream.shutdown(Shutdown::Write)?;
    let deadline = Instant::now() + Duration::from_millis(100);
    let mut budget = 64 * 1024;
    let mut bytes = [0; 4096];
    while budget > 0 {
        let Ok(timeout) = remaining(deadline) else {
            break;
        };
        stream.set_read_timeout(Some(timeout))?;
        let count = budget.min(bytes.len());
        match stream.read(&mut bytes[..count]) {
            Ok(0) | Err(_) => break,
            Ok(n) => budget -= n,
        }
    }
    Ok(())
}

pub fn listener(cfg: &Config) -> io::Result<TcpListener> {
    let listener = TcpListener::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, cfg.control_port))?;
    listener.set_nonblocking(true)?;
    Ok(listener)
}

pub fn request(
    port: u16,
    host_port: u16,
    token: &str,
    command: &str,
    args: &str,
    timeout: Duration,
) -> io::Result<String> {
    let deadline = Instant::now() + timeout;
    let mut stream = TcpStream::connect_timeout(
        &SocketAddrV4::new(Ipv4Addr::LOCALHOST, port).into(),
        remaining(deadline)?,
    )?;
    stream.set_write_timeout(Some(remaining(deadline)?))?;
    let body = format!("{{\"command\":{},\"args\":{}}}", json_string(command), args);
    if body.len() > BODY_LIMIT {
        return Err(err("command exceeds 16KiB"));
    }
    let host = format!("127.0.0.1:{host_port}");
    write!(stream, "POST /api/command HTTP/1.1\r\nHost: {host}\r\nOrigin: http://{host}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len())?;
    stream.flush()?;
    let (head, body) = read_until_header(&mut stream, deadline)?;
    let mut lines = head.split("\r\n");
    if lines.next() != Some("HTTP/1.1 200 OK") {
        return Err(err("control command rejected; no redirects permitted"));
    }
    let h = headers(lines)?;
    let size = h
        .get("content-length")
        .and_then(|v| v.parse::<usize>().ok())
        .filter(|n| *n <= RESPONSE_LIMIT)
        .ok_or_else(|| err("bounded control response required"))?;
    String::from_utf8(read_body(&mut stream, body, size, deadline)?)
        .map_err(|_| err("invalid control response"))
}

pub fn request_peer(cfg: &Config, command: &str, args: &str) -> io::Result<String> {
    request(
        cfg.forward_control_port,
        cfg.remote_control_port,
        &cfg.token(true)?,
        command,
        args,
        Duration::from_secs(cfg.timeout as u64),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;

    fn exchange(extra: &str, method: &str, path: &str, body: &str) -> io::Result<Request> {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let mut client = TcpStream::connect(l.local_addr().unwrap()).unwrap();
        let request =
            format!("{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n{extra}\r\n{body}");
        client.write_all(request.as_bytes()).unwrap();
        let (mut server, _) = l.accept().unwrap();
        recv_until(
            &mut server,
            port,
            "test-token",
            Instant::now() + Duration::from_millis(100),
        )
    }

    #[test]
    fn public_assets_carry_no_token_and_require_loopback_host() {
        assert_eq!(exchange("", "GET", "/", "").unwrap().path, "/");
        assert!(exchange("", "GET", "/api/status", "").is_err());
        assert!(exchange("Origin: https://evil.invalid\r\n", "GET", "/", "").is_err());
        assert!(exchange("Host: evil.invalid\r\n", "GET", "/", "").is_err());
    }

    #[test]
    fn rejects_ambiguous_framing_even_duplicate_transfer_encoding() {
        for header in [
            "Transfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n",
            "Content-Length: 0\r\nContent-Length: 0\r\n",
            "Content-Length: 1\r\n",
            "X-Test : value\r\n",
        ] {
            assert!(
                exchange(header, "GET", "/", "").is_err(),
                "accepted {header:?}"
            );
        }
        assert!(exchange("", "GET", "/", "unexpected").is_err());
    }

    #[test]
    fn slow_headers_have_one_absolute_deadline() {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = TcpStream::connect(l.local_addr().unwrap()).unwrap();
        let writer = thread::spawn(move || {
            for _ in 0..20 {
                if client.write_all(b"G").is_err() {
                    break;
                }
                thread::sleep(Duration::from_millis(15));
            }
        });
        let (mut server, _) = l.accept().unwrap();
        let start = Instant::now();
        assert!(recv_until(
            &mut server,
            1234,
            "secret",
            start + Duration::from_millis(80)
        )
        .is_err());
        assert!(start.elapsed() < Duration::from_millis(250));
        drop(server);
        writer.join().unwrap();
    }

    #[test]
    fn rejects_redirect_and_status_code_substrings() {
        for status in ["HTTP/1.1 302 200 Redirect", "HTTP/1.1 403 200 Forbidden"] {
            let l = TcpListener::bind("127.0.0.1:0").unwrap();
            let port = l.local_addr().unwrap().port();
            let response = status.to_owned();
            let server = thread::spawn(move || {
                let (mut s, _) = l.accept().unwrap();
                let mut request = [0; 4096];
                assert!(s.read(&mut request).unwrap() > 0);
                write!(s, "{response}\r\nContent-Length: 2\r\n\r\n{{}}").unwrap();
            });
            assert!(request(port, port, "secret", "status", "{}", Duration::from_secs(1)).is_err());
            server.join().unwrap();
        }
    }

    #[test]
    fn compares_full_tokens() {
        assert!(same("Bearer secret", "Bearer secret"));
        assert!(!same("Bearer secret", "Bearer secretx"));
    }
}
