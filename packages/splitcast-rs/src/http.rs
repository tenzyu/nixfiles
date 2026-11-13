use serde_json::Value;
use std::io::{self, Read};
use std::time::Duration;

pub fn get_json(port: u16, path: &str, timeout: Duration, limit: usize) -> io::Result<Value> {
    if !path.starts_with('/') || path.starts_with("//") || path.contains(['\r', '\n', '\0']) {
        return Err(io::Error::other("invalid loopback service path"));
    }
    let config = ureq::Agent::config_builder()
        .proxy(None)
        .max_redirects(0)
        .max_response_header_size(20 * 1024)
        .max_idle_connections(0)
        .timeout_global(Some(timeout))
        .http_status_as_error(false)
        .build();
    let agent: ureq::Agent = config.into();
    let mut response = agent
        .get(format!("http://127.0.0.1:{port}{path}"))
        .call()
        .map_err(|_| io::Error::other("loopback service request failed"))?;
    if response.status() != 200 {
        return Err(io::Error::other(
            "loopback service rejected request; redirects are forbidden",
        ));
    }
    let mut body = Vec::new();
    response
        .body_mut()
        .as_reader()
        .take(limit.saturating_add(1) as u64)
        .read_to_end(&mut body)
        .map_err(|_| io::Error::other("loopback response failed or exceeded its deadline"))?;
    if body.len() > limit {
        return Err(io::Error::other("loopback response exceeds its byte limit"));
    }
    serde_json::from_slice(&body).map_err(|_| io::Error::other("invalid loopback JSON"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io::Write, net::TcpListener, thread, time::Instant};
    fn response(bytes: &'static [u8]) -> (u16, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let thread = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0; 4096];
            assert!(stream.read(&mut request).unwrap() > 0);
            stream.write_all(bytes).unwrap();
        });
        (port, thread)
    }
    #[test]
    fn accepts_chunked_json_and_rejects_oversized_body() {
        let(port,server)=response(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\nc\r\n{\"items\":[]}\r\n0\r\n\r\n");
        assert_eq!(
            get_json(port, "/paths", Duration::from_secs(1), 128).unwrap()["items"],
            serde_json::json!([])
        );
        server.join().unwrap();
        let (port, server) = response(
            b"HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\n{\"items\":[]}",
        );
        assert!(get_json(port, "/paths", Duration::from_secs(1), 4).is_err());
        server.join().unwrap();
    }
    #[test]
    fn never_follows_redirects() {
        let target = TcpListener::bind("127.0.0.1:0").unwrap();
        target.set_nonblocking(true).unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let address = target.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0; 4096];
            assert!(stream.read(&mut request).unwrap() > 0);
            write!(stream,"HTTP/1.1 302 Found\r\nLocation: http://{address}/secret\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
        });
        assert!(get_json(port, "/paths", Duration::from_secs(1), 128).is_err());
        server.join().unwrap();
        assert!(target.accept().is_err());
    }
    #[test]
    fn slow_response_body_does_not_extend_the_global_deadline() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0; 4096];
            assert!(stream.read(&mut request).unwrap() > 0);
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n")
                .unwrap();
            for _ in 0..100 {
                if stream.write_all(b" ").is_err() {
                    break;
                }
                thread::sleep(Duration::from_millis(10));
            }
        });
        let now = Instant::now();
        assert!(get_json(port, "/paths", Duration::from_millis(100), 128).is_err());
        assert!(now.elapsed() < Duration::from_millis(500));
        server.join().unwrap();
    }
}
