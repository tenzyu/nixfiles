//! Production audio lives in an owned private server, never the player's graph.
use crate::{
    config::{self, Config},
    media, state,
};
use std::fs;
use std::io::{self, Read};
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::unix::net::UnixStream;

fn root(cfg: &Config) -> std::path::PathBuf {
    cfg.state_dir.join("production-audio")
}
fn socket(cfg: &Config) -> std::path::PathBuf {
    root(cfg).join("native.sock")
}

pub fn client(cfg: &Config, argv: Vec<String>) -> Vec<String> {
    let mut args = vec![
        "env".into(),
        format!("PULSE_SERVER=unix:{}", socket(cfg).display()),
        format!("PULSE_COOKIE={}", root(cfg).join("cookie").display()),
    ];
    args.extend(argv);
    args
}

pub fn cleanup_socket(cfg: &Config) -> io::Result<()> {
    let path = socket(cfg);
    match fs::symlink_metadata(&path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
        Ok(meta) => {
            unsafe extern "C" {
                fn getuid() -> u32;
            }
            if !meta.file_type().is_socket() || meta.uid() != unsafe { getuid() } {
                return Err(io::Error::other(
                    "refusing non-owned production audio socket",
                ));
            }
        }
    }
    if UnixStream::connect(&path).is_ok() {
        return Err(io::Error::other(
            "production audio socket is still owned by a live server",
        ));
    }
    fs::remove_file(path)
}

pub fn server(cfg: &Config) -> io::Result<Vec<String>> {
    let root = root(cfg);
    state::private_directory(&root)?;
    state::private_directory(&root.join("runtime"))?;
    cleanup_socket(cfg)?;
    let cookie = root.join("cookie");
    let mut random = [0; 256];
    fs::File::open("/dev/urandom")?.read_exact(&mut random)?;
    state::atomic_file(&cookie, random)?;
    let script=format!("load-module module-native-protocol-unix socket={} auth-anonymous=0 auth-cookie={}\nload-module module-null-sink sink_name={} rate=48000 channels=1\nset-default-sink {}\n",config::json_string(&socket(cfg).to_string_lossy()),config::json_string(&cookie.to_string_lossy()),cfg.processed_sink,cfg.processed_sink);
    let script_path = root.join("server.pa");
    state::atomic_file(&script_path, &script)?;
    Ok(vec![
        "env".into(),
        format!("PULSE_RUNTIME_PATH={}", root.join("runtime").display()),
        format!("PULSE_STATE_PATH={}", root.display()),
        "pulseaudio".into(),
        "-n".into(),
        "--daemonize=no".into(),
        "--use-pid-file=no".into(),
        "--exit-idle-time=-1".into(),
        "--realtime=no".into(),
        "--high-priority=no".into(),
        "--disable-shm=yes".into(),
        "--log-target=stderr".into(),
        format!("--file={}", script_path.display()),
    ])
}

pub fn ready(cfg: &Config) -> io::Result<bool> {
    let argv = client(
        cfg,
        vec![
            "pactl".into(),
            "-f".into(),
            "json".into(),
            "list".into(),
            "sinks".into(),
        ],
    );
    let value: serde_json::Value = serde_json::from_str(&media::command_checked(&argv)?)
        .map_err(|_| io::Error::other("invalid private audio observation"))?;
    Ok(value.as_array().is_some_and(|sinks| {
        sinks.len() == 1 && sinks[0]["name"].as_str() == Some(&cfg.processed_sink)
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::OwnedProcess;
    use std::time::{Duration, Instant};

    #[test]
    #[ignore = "runs an actual isolated PulseAudio daemon; requires pulseaudio and pactl in PATH"]
    fn private_audio_dies_with_its_owned_server() {
        let mut cfg = Config::parse(include_bytes!("../tests/agent-example.json")).unwrap();
        cfg.role = "production".into();
        cfg.state_dir =
            std::env::temp_dir().join(format!("splitcast-private-audio-{}", std::process::id()));
        state::private_directory(&cfg.state_dir).unwrap();
        let mut process = OwnedProcess::spawn(&server(&cfg).unwrap()).unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while !ready(&cfg).unwrap_or(false) && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(30));
        }
        assert!(
            ready(&cfg).unwrap(),
            "private processed sink did not become ready"
        );
        assert!(UnixStream::connect(socket(&cfg)).is_ok());
        process.stop(Duration::from_millis(100)).unwrap();
        assert!(
            UnixStream::connect(socket(&cfg)).is_err(),
            "audio server survived its owned process group"
        );
        cleanup_socket(&cfg).unwrap();
        assert!(!socket(&cfg).exists());
        fs::remove_dir_all(&cfg.state_dir).unwrap();
    }
}
