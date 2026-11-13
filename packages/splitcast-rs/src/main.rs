use serde_json::{json, Value};
use splitcast_rs_core::{
    agent, config, control, protocol::Invocation, tui, Lifecycle, Role, Session,
};
use std::io;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

struct Cli {
    config: PathBuf,
    command: String,
    args: Value,
    destination: Option<PathBuf>,
    offline: bool,
}

fn parse(mut args: Vec<String>) -> io::Result<Cli> {
    let mut config = None;
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--" {
            args.remove(i);
            break;
        }
        if args[i] == "--config" || args[i].starts_with("--config=") {
            if config.is_some() {
                return Err(invalid("supply --config only once"));
            }
            let value = if args[i] == "--config" {
                args.remove(i);
                if i >= args.len() {
                    return Err(invalid("--config requires a path"));
                }
                args.remove(i)
            } else {
                args.remove(i).trim_start_matches("--config=").to_owned()
            };
            if value.is_empty() {
                return Err(invalid("--config requires a path"));
            }
            config = Some(PathBuf::from(value));
        } else {
            i += 1;
        }
    }
    let config=config.ok_or_else(||invalid("usage: splitcast --config FILE.toml agent|tui|doctor|devices|routes|prepare|start|stop|status"))?;
    if args.is_empty() {
        return Err(invalid("command required"));
    }
    let command = args.remove(0);
    let mut payload = json!({});
    let mut destination = None;
    let mut offline = false;
    match command.as_str() {
        "agent" | "tui" | "ui" | "validate" | "cleanup" | "prepare" | "stop" | "status"
        | "heartbeat" | "devices" => {}
        "doctor" => {
            if args.first().map(String::as_str) == Some("--offline") {
                args.remove(0);
                offline = true;
            }
        }
        "start" => {
            let output = if args.first().map(String::as_str) == Some("--output") {
                args.remove(0);
                if args.is_empty() {
                    return Err(invalid("--output requires recording or twitch"));
                }
                args.remove(0)
            } else if args
                .first()
                .is_some_and(|s| s == "recording" || s == "twitch")
            {
                args.remove(0)
            } else {
                "recording".into()
            };
            payload["output"] = json!(output);
        }
        "routes" => {
            if args.first().map(String::as_str) == Some("--settings") {
                args.remove(0);
                if args.is_empty() {
                    return Err(invalid("--settings requires JSON selections"));
                }
                payload["settings"] = serde_json::from_str(&args.remove(0))
                    .map_err(|_| invalid("invalid settings JSON"))?;
            }
        }
        "mic" | "tts" => {
            payload["action"] = json!(if args.is_empty() {
                "status".into()
            } else {
                args.remove(0)
            });
        }
        "say" | "overlay" => {
            if args.is_empty() {
                return Err(invalid("text argument required"));
            }
            payload["text"] = json!(args.remove(0));
            if command == "say" && args.first().map(String::as_str) == Some("--id") {
                args.remove(0);
                if args.is_empty() {
                    return Err(invalid("--id requires a speech id"));
                }
                payload["id"] = json!(args.remove(0));
            }
        }
        "preview" | "diagnostics" => {
            if args.first().map(String::as_str) == Some("--output") {
                args.remove(0);
                if args.is_empty() {
                    return Err(invalid("--output requires a path"));
                }
                destination = Some(PathBuf::from(args.remove(0)));
            }
        }
        _ => return Err(invalid("unknown SplitCast command")),
    }
    if !args.is_empty() {
        return Err(invalid("unexpected extra arguments"));
    }
    Ok(Cli {
        config,
        command,
        args: payload,
        destination,
        offline,
    })
}

fn request(cfg: &config::Config, name: &str, args: &str) -> io::Result<String> {
    let value: Value = serde_json::from_str(args).map_err(|_| invalid("invalid command JSON"))?;
    Invocation::parse(name, &value, cfg.tts_max_text as usize)?;
    control::request(
        cfg.control_port,
        cfg.control_port,
        &cfg.token(false)?,
        name,
        args,
        Duration::from_secs(180),
    )
}

fn run() -> io::Result<()> {
    unsafe {
        libc::umask(0o077);
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args == ["selfcheck"] {
        let mut session = Session::new(Role::Production);
        session
            .prepare(None, std::time::Instant::now(), Duration::from_secs(30))
            .unwrap();
        session.prepared().unwrap();
        session.stop().unwrap();
        session.stopped().unwrap();
        assert_eq!(session.state(), Lifecycle::Idle);
        println!("splitcast lifecycle selfcheck passed; no media started");
        return Ok(());
    }
    let cli = parse(args)?;
    let cfg = config::Config::load(&cli.config)?;
    match cli.command.as_str() {
        "validate" => {
            println!(
                "{}",
                json!({"valid":true,"role":cfg.role,"control_port":cfg.control_port,"remote_control_port":cfg.remote_control_port,"ssh_host":cfg.ssh_host})
            );
            return Ok(());
        }
        "agent" => return agent::serve(cfg),
        "cleanup" => return agent::cleanup_after_exit(cfg),
        "tui" => {
            return tui::run_with(io::stdin().lock(), io::stdout().lock(), |name, args| {
                request(&cfg, name, args)
            })
        }
        "ui" => {
            println!("http://127.0.0.1:{}/", cfg.control_port);
            return Ok(());
        }
        "doctor" if cli.offline => {
            println!("{}", agent::doctor(&cfg)?);
            return Ok(());
        }
        _ => {}
    }
    let response = request(&cfg, &cli.command, &cli.args.to_string())?;
    if let Some(destination) = cli.destination {
        if cli.command == "preview" {
            return Err(invalid(
                "preview file export is not yet available; use the authenticated preview view",
            ));
        }
        splitcast_rs_core::state::atomic_file(&destination, &response)?;
        println!("{}", json!({"path":destination.to_string_lossy()}));
    } else {
        println!("{response}");
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{}", json!({"error":error.to_string()}));
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cli_rejects_ignored_options() {
        for args in [
            vec!["--config", "x", "--config=y", "status"],
            vec!["status", "--config=x", "--output", "twitch"],
            vec!["agent", "--config=x", "garbage"],
            vec!["start", "--config=x", "--output"],
        ] {
            assert!(parse(args.into_iter().map(str::to_owned).collect()).is_err());
        }
    }
    #[test]
    fn config_can_follow_command_without_implicit_publication() {
        let cli = parse(
            ["start", "--config=example.toml"]
                .into_iter()
                .map(str::to_owned)
                .collect(),
        )
        .unwrap();
        assert_eq!(cli.args["output"], "recording");
    }
}
