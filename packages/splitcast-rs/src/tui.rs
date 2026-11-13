//! Line-mode client with no terminal dependencies. Authentication belongs to the dispatcher.
use serde_json::{json, Value};
use std::io::{self, BufRead, Read, Write};

const MENU: &str = "\n1 Refresh status/routes   2 Discover devices   3 Select route settings\n4 Doctor   5 Prepare   6 Start RECORDING   7 Stop   8 Preview info\n9 Microphone   10 TTS   11 Overlay text   12 Say text\n13 Twitch (separate confirmation)   0 Quit\nChoice: ";

/// Drive the real menu with buffered input, a writer, and the local authenticated
/// control dispatcher. Dispatch receives command and JSON args, and returns JSON.
/// EOF or Quit exits without stopping, starting, or saving the session.
pub fn run_with<R, W, F>(mut input: R, mut output: W, mut dispatch: F) -> io::Result<()>
where
    R: BufRead,
    W: Write,
    F: FnMut(&str, &str) -> io::Result<String>,
{
    writeln!(output, "SplitCast Rust terminal | Recording is the default. No automatic Twitch.\nLine mode. Enter a number; EOF exits. Quit leaves the session unchanged.")?;
    refresh(&mut output, &mut dispatch)?;
    loop {
        let Some(choice) = prompt(&mut input, &mut output, MENU)? else {
            return Ok(());
        };
        let result = match choice.as_str() {
            "0" | "q" | "quit" => return Ok(()),
            "" => continue,
            "1" => refresh(&mut output, &mut dispatch),
            "2" => discover(&mut output, &mut dispatch),
            "3" => select(&mut input, &mut output, &mut dispatch),
            "4" => perform(&mut output, &mut dispatch, "doctor", json!({})),
            "5" => perform(&mut output, &mut dispatch, "prepare", json!({})),
            "6" => perform(
                &mut output,
                &mut dispatch,
                "start",
                json!({"output":"recording"}),
            ),
            "7" => perform(&mut output, &mut dispatch, "stop", json!({})),
            "8" => perform(&mut output, &mut dispatch, "preview", json!({})),
            "9" => action(
                &mut input,
                &mut output,
                &mut dispatch,
                "mic",
                &["status", "mute", "unmute"],
            ),
            "10" => action(
                &mut input,
                &mut output,
                &mut dispatch,
                "tts",
                &["status", "on", "off", "mute", "unmute", "skip", "clear"],
            ),
            "11" => text(&mut input, &mut output, &mut dispatch, "overlay", 1000),
            "12" => text(&mut input, &mut output, &mut dispatch, "say", 500),
            "13" => {
                match prompt(
                    &mut input,
                    &mut output,
                    "Twitch publishes publicly. Type TWITCH to start, anything else cancels: ",
                )? {
                    Some(word) if word == "TWITCH" => perform(
                        &mut output,
                        &mut dispatch,
                        "start",
                        json!({"output":"twitch"}),
                    ),
                    _ => writeln!(output, "Twitch cancelled."),
                }
            }
            _ => writeln!(output, "Unknown choice. Use the displayed numbers."),
        };
        if let Err(error) = result {
            if matches!(
                error.kind(),
                io::ErrorKind::BrokenPipe | io::ErrorKind::UnexpectedEof
            ) {
                return Err(error);
            }
            // Never echo transport errors, which can contain authentication details.
            writeln!(output, "Operation failed ({:?}). Check the local agent, status and Doctor. No automatic retry.", error.kind())?;
        }
    }
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn request<F>(dispatch: &mut F, command: &str, args: Value) -> io::Result<Value>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    let body = dispatch(command, &args.to_string())?;
    if body.len() > 4 * 1024 * 1024 {
        return Err(invalid("oversized response"));
    }
    let value: Value = serde_json::from_str(&body).map_err(|_| invalid("invalid JSON response"))?;
    if !value.is_object() {
        return Err(invalid("expected object response"));
    }
    if value
        .get("error")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty())
        && value.get("state").is_none()
    {
        return Err(invalid("agent rejected command"));
    }
    Ok(value)
}

fn prompt<R: BufRead, W: Write>(
    input: &mut R,
    output: &mut W,
    label: &str,
) -> io::Result<Option<String>> {
    write!(output, "{label}")?;
    output.flush()?;
    let mut line = String::new();
    if input.take(4097).read_line(&mut line)? == 0 {
        return Ok(None);
    }
    if line.len() > 4096 {
        return Err(invalid("input exceeds 4096 bytes"));
    }
    if !line.ends_with('\n') {
        return Ok(None);
    }
    let line = line.trim_end_matches(['\r', '\n']);
    if line.chars().any(unsafe_character) {
        return Err(invalid("control characters forbidden"));
    }
    Ok(Some(line.to_owned()))
}

fn unsafe_character(c: char) -> bool {
    c.is_control()
        || matches!(c, '\u{200b}'..='\u{200f}' | '\u{2028}'..='\u{202e}' | '\u{2060}'..='\u{206f}' | '\u{feff}')
}

fn escaped(value: &str) -> String {
    let mut output = String::new();
    for c in value.chars().take(300) {
        if unsafe_character(c) {
            output.extend(c.escape_default());
        } else {
            output.push(c);
        }
    }
    if value.chars().count() > 300 {
        output.push_str("...");
    }
    output
}

fn string(value: &Value) -> String {
    value.as_str().map(escaped).unwrap_or_else(|| "?".into())
}

fn list(value: &Value, separator: &str) -> String {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .take(20)
                .map(string)
                .collect::<Vec<_>>()
                .join(separator)
        })
        .unwrap_or_else(|| "?".into())
}

fn status<W: Write>(output: &mut W, value: &Value) -> io::Result<()> {
    writeln!(
        output,
        "State {} | role {} | output {}",
        string(&value["state"]),
        string(&value["role"]),
        string(&value["output"])
    )?;
    if let Some(error) = value["error"].as_str().filter(|s| !s.is_empty()) {
        writeln!(output, "Agent error: {}", escaped(error))?;
    }
    if let Some(warnings) = value["warnings"].as_array() {
        for warning in warnings.iter().take(20) {
            writeln!(output, "Warning: {}", string(warning))?;
        }
    }
    Ok(())
}

fn table<W: Write>(output: &mut W, value: &Value) -> io::Result<()> {
    writeln!(
        output,
        "\nROUTE | SOURCE -> PROCESSORS -> TARGETS | ENABLED"
    )?;
    let Some(routes) = value["routes"].as_array() else {
        return writeln!(
            output,
            "Route table unavailable. Agent must support routes/selection."
        );
    };
    for route in routes.iter().take(20) {
        writeln!(
            output,
            "{} | {} -> {} -> {} | {}",
            string(&route["id"]),
            string(&route["source"]),
            list(&route["processors"], " -> "),
            list(&route["targets"], ", "),
            route["enabled"]
                .as_bool()
                .map(|v| if v { "on" } else { "off" })
                .unwrap_or("?")
        )?;
    }
    for (section, key) in [
        ("peer", "ssh_host"),
        ("capture", "target"),
        ("capture", "game_audio"),
        ("audio", "mic_source"),
        ("audio", "tts_sink"),
        ("camera", "location"),
        ("camera", "device"),
        ("camera", "mode"),
    ] {
        if let Some(value) = value["selection"][section][key].as_str() {
            writeln!(output, "  {section}.{key} = {}", escaped(value))?;
        }
    }
    writeln!(
        output,
        "Only approved route templates are selectable. Local game/audio defaults are not changed."
    )
}

fn refresh<W: Write, F>(output: &mut W, dispatch: &mut F) -> io::Result<()>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    match request(dispatch, "status", json!({})) {
        Ok(value) => status(output, &value)?,
        Err(_) => writeln!(
            output,
            "Status unavailable. Check the local authenticated agent."
        )?,
    }
    match request(dispatch, "routes", json!({})) {
        Ok(value) => table(output, &value),
        Err(_) => writeln!(
            output,
            "Routes unavailable. Refresh after connecting the agent."
        ),
    }
}

fn perform<W: Write, F>(
    output: &mut W,
    dispatch: &mut F,
    command: &str,
    args: Value,
) -> io::Result<()>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    let value = request(dispatch, command, args)?;
    writeln!(output, "{command} accepted.")?;
    if value.get("state").is_some() {
        status(output, &value)?;
    }
    if command == "doctor" {
        if let Some(ok) = value["ok"].as_bool() {
            writeln!(output, "Doctor OK = {ok}")?;
        }
        if let Some(missing) = value["missing"].as_array() {
            for name in missing.iter().take(50) {
                writeln!(output, "Missing: {}", string(name))?;
            }
        }
        if let Some(checks) = value["checks"].as_array() {
            for check in checks.iter().take(50) {
                writeln!(
                    output,
                    "{} | OK {} | {}",
                    string(&check["name"]),
                    check["ok"].as_bool().unwrap_or(false),
                    string(&check["action"])
                )?;
            }
        }
    } else if command == "preview" {
        writeln!(output, "Preview received. Image rendering is not supported in line mode; use the authenticated preview client. No file was written.")?;
    } else if command == "mic" {
        if let Some(muted) = value["muted"].as_bool() {
            writeln!(output, "Microphone muted = {muted}")?;
        }
    } else if command == "tts" {
        for key in ["enabled", "muted", "queued", "queue_length"] {
            if value[key].is_boolean() || value[key].is_number() {
                writeln!(output, "TTS {key} = {}", value[key])?;
            }
        }
    }
    Ok(())
}

fn action<R: BufRead, W: Write, F>(
    input: &mut R,
    output: &mut W,
    dispatch: &mut F,
    command: &str,
    actions: &[&str],
) -> io::Result<()>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    for (i, action) in actions.iter().enumerate() {
        writeln!(output, "{} {action}", i + 1)?;
    }
    let Some(answer) = prompt(input, output, "Action (0 cancels): ")? else {
        return Ok(());
    };
    if answer == "0" {
        return Ok(());
    }
    let Some(action) = answer
        .parse::<usize>()
        .ok()
        .and_then(|n| n.checked_sub(1))
        .and_then(|n| actions.get(n))
    else {
        return writeln!(output, "Unknown action.");
    };
    perform(output, dispatch, command, json!({"action":action}))
}

fn text<R: BufRead, W: Write, F>(
    input: &mut R,
    output: &mut W,
    dispatch: &mut F,
    command: &str,
    max: usize,
) -> io::Result<()>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    let Some(text) = prompt(input, output, "Text (empty cancels): ")? else {
        return Ok(());
    };
    if text.is_empty() {
        return Ok(());
    }
    if text.chars().count() > max {
        return writeln!(output, "Text exceeds {max} characters. Nothing sent.");
    }
    perform(output, dispatch, command, json!({"text":text}))
}

#[derive(Clone, Copy)]
enum Selection {
    Target,
    Application,
    Microphone,
    TtsSink,
    Camera,
    CameraEnabled,
    CameraMode,
    TtsEnabled,
    TtsMix,
    CameraLocation,
}

impl Selection {
    fn parse(number: &str) -> Option<Self> {
        Some(match number {
            "1" => Self::Target,
            "2" => Self::Application,
            "3" => Self::Microphone,
            "4" => Self::TtsSink,
            "5" => Self::Camera,
            "6" => Self::CameraEnabled,
            "7" => Self::CameraMode,
            "8" => Self::TtsEnabled,
            "9" => Self::TtsMix,
            "10" => Self::CameraLocation,
            _ => return None,
        })
    }

    fn field(self) -> (&'static str, &'static str) {
        match self {
            Self::Target => ("capture", "target"),
            Self::Application => ("capture", "game_audio"),
            Self::Microphone => ("audio", "mic_source"),
            Self::TtsSink => ("audio", "tts_sink"),
            Self::Camera => ("camera", "device"),
            Self::CameraEnabled => ("camera", "enabled"),
            Self::CameraMode => ("camera", "mode"),
            Self::TtsEnabled => ("tts", "enabled"),
            Self::TtsMix => ("tts", "mix_remote"),
            Self::CameraLocation => ("camera", "location"),
        }
    }
}

fn idle<W: Write, F>(output: &mut W, dispatch: &mut F) -> io::Result<bool>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    let value = request(dispatch, "status", json!({}))?;
    if value["state"].as_str() == Some("idle") {
        return Ok(true);
    }
    writeln!(
        output,
        "Selection changes require Idle. Stop first; nothing saved."
    )?;
    Ok(false)
}

fn select<R: BufRead, W: Write, F>(
    input: &mut R,
    output: &mut W,
    dispatch: &mut F,
) -> io::Result<()>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    if !idle(output, dispatch)? {
        return Ok(());
    }
    let routes = request(dispatch, "routes", json!({}))?;
    if !routes["selection"].is_object() {
        return writeln!(
            output,
            "Selection unavailable. Update the agent; nothing saved."
        );
    }
    table(output, &routes)?;
    let Some(number) = prompt(input, output, "1 GSR target   2 Game application audio   3 Raw microphone\n4 Local TTS sink   5 Camera device   6 Camera enabled\n7 Camera processor (hardware/H264)   8 TTS enabled\n9 TTS target (local or local + OBS)   10 Camera host\nSelection (0 cancels): ")? else { return Ok(()); };
    if number == "0" {
        return Ok(());
    }
    let Some(selection) = Selection::parse(&number) else {
        return writeln!(
            output,
            "Unknown selection. Arbitrary routes are not supported."
        );
    };
    let choices: Vec<(Value, String)> = match selection {
        Selection::CameraEnabled | Selection::TtsEnabled => vec![
            (json!(false), "Disabled".into()),
            (json!(true), "Enabled".into()),
        ],
        Selection::TtsMix => vec![
            (json!(false), "Local TTS only".into()),
            (json!(true), "Local TTS + OBS TTS mix".into()),
        ],
        Selection::CameraMode => vec![
            (json!("hardware"), "Camera hardware H264".into()),
            (json!("h264"), "Selected H264 encoder".into()),
        ],
        Selection::CameraLocation => vec![
            (json!("capture"), "Capture host".into()),
            (json!("production"), "Production host".into()),
        ],
        _ => {
            let devices = request(dispatch, "devices", json!({}))?;
            let host = if matches!(selection, Selection::Camera) {
                let role = routes["selection"]["camera"]["location"]
                    .as_str()
                    .ok_or_else(|| invalid("missing camera location"))?;
                ["local", "remote"]
                    .iter()
                    .map(|key| &devices[*key])
                    .find(|host| host["role"].as_str() == Some(role))
            } else {
                devices.get("local")
            };
            let Some(host) = host else {
                return writeln!(
                    output,
                    "Selected host discovery unavailable. Nothing saved."
                );
            };
            device_choices(host, selection)
        }
    };
    if choices.is_empty() {
        return writeln!(
            output,
            "No safe exact choices discovered. Run Discover/Doctor; nothing saved."
        );
    }
    for (i, (_, label)) in choices.iter().enumerate() {
        writeln!(output, "{} {}", i + 1, escaped(label))?;
    }
    let Some(answer) = prompt(input, output, "Choose exact device/value (0 cancels): ")? else {
        return Ok(());
    };
    if answer == "0" {
        return Ok(());
    }
    let Some((value, _)) = answer
        .parse::<usize>()
        .ok()
        .and_then(|n| n.checked_sub(1))
        .and_then(|n| choices.get(n))
    else {
        return writeln!(output, "Unknown choice. Nothing saved.");
    };
    if !idle(output, dispatch)? {
        return Ok(());
    }
    let (section, key) = selection.field();
    let args = json!({"settings":{section:{key:value}}});
    let saved = request(dispatch, "routes", args)?;
    writeln!(output, "Selection saved by the agent.")?;
    table(output, &saved)
}

fn safe_value(value: &str) -> bool {
    !value.is_empty() && value.len() <= 256 && !value.chars().any(unsafe_character)
}

fn device_choices(host: &Value, selection: Selection) -> Vec<(Value, String)> {
    let (collection, field) = match selection {
        Selection::Target => ("gsr_targets", "target"),
        Selection::Application => ("audio_apps", "name"),
        Selection::Microphone => ("sources", "name"),
        Selection::TtsSink => ("sinks", "name"),
        Selection::Camera => ("cameras", "device"),
        _ => return vec![],
    };
    let Some(items) = host[collection].as_array() else {
        return vec![];
    };
    items
        .iter()
        .take(200)
        .filter_map(|item| {
            let raw = item.as_str().or_else(|| item[field].as_str()).or_else(|| {
                if matches!(selection, Selection::Target) {
                    item["name"].as_str()
                } else {
                    None
                }
            })?;
            if !safe_value(raw) {
                return None;
            }
            let value = match selection {
                Selection::Application => {
                    let name = raw.strip_prefix("app:").unwrap_or(raw);
                    if name.is_empty()
                        || name.eq_ignore_ascii_case("splitcast-tts")
                        || name.contains(['|', ';'])
                    {
                        return None;
                    }
                    format!("app:{name}")
                }
                Selection::Microphone | Selection::TtsSink => {
                    if !raw
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"._:-".contains(&b))
                    {
                        return None;
                    }
                    if matches!(selection, Selection::Microphone)
                        && ["monitor", "easyeffects", "rnnoise", "splitcast_"]
                            .iter()
                            .any(|part| raw.to_lowercase().contains(part))
                    {
                        return None;
                    }
                    raw.to_owned()
                }
                Selection::Camera
                    if !raw.starts_with("/dev/v4l/by-id/")
                        || raw.split('/').any(|part| part == "..") =>
                {
                    return None
                }
                _ => raw.to_owned(),
            };
            if !safe_value(&value) {
                return None;
            }
            let label = match item["description"].as_str().filter(|s| !s.is_empty()) {
                Some(description) => format!("{value} ({})", escaped(description)),
                None => value.clone(),
            };
            Some((json!(value), label))
        })
        .collect()
}

fn discover<W: Write, F>(output: &mut W, dispatch: &mut F) -> io::Result<()>
where
    F: FnMut(&str, &str) -> io::Result<String>,
{
    let devices = request(dispatch, "devices", json!({}))?;
    for key in ["local", "remote"] {
        let Some(host) = devices.get(key).filter(|host| host.is_object()) else {
            continue;
        };
        writeln!(output, "{key} host ({})", string(&host["role"]))?;
        for (label, selection) in [
            ("GSR target", Selection::Target),
            ("Application audio", Selection::Application),
            ("Raw microphone", Selection::Microphone),
            ("TTS sink", Selection::TtsSink),
            ("Camera", Selection::Camera),
        ] {
            writeln!(output, "  {label}")?;
            let choices = device_choices(host, selection);
            if choices.is_empty() {
                writeln!(output, "    No safe structured choices available.")?;
            }
            for (i, (_, name)) in choices.iter().enumerate() {
                writeln!(output, "    {} {}", i + 1, escaped(name))?;
            }
        }
        if let Some(errors) = host["errors"].as_array() {
            for error in errors.iter().take(20) {
                writeln!(output, "Discovery error: {}", string(error))?;
            }
        }
    }
    if devices.get("local").is_none() {
        writeln!(output, "Structured local/remote discovery is unavailable. Update the agent; no device selection attempted.")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Cursor;

    fn fixture(command: &str) -> Value {
        match command {
            "status" => json!({"state":"idle","role":"capture","output":null}),
            "routes" => {
                json!({"routes":[{"id":"game","source":"game.av","processors":["capture.gpu","transport.rtmp"],"targets":["local.headphones","obs.game"],"enabled":true}],"selection":{"camera":{"location":"capture"}}})
            }
            "devices" => {
                json!({"local":{"role":"capture","gsr_targets":["DP-1"],"audio_apps":["osu!"],"sources":[{"name":"alsa_input.usb","description":"Raw mic"}],"sinks":[{"name":"headphones"}],"cameras":[{"device":"/dev/v4l/by-id/camera"}]}})
            }
            _ => json!({"ok":true}),
        }
    }

    fn drive(script: &str, state: &str) -> (String, Vec<(String, Value)>) {
        let mut calls = Vec::new();
        let mut output = Vec::new();
        run_with(Cursor::new(script), &mut output, |command, args| {
            let args = serde_json::from_str(args).unwrap();
            calls.push((command.to_owned(), args));
            let mut answer = fixture(command);
            if command == "status" {
                answer["state"] = json!(state);
            }
            Ok(answer.to_string())
        })
        .unwrap();
        (String::from_utf8(output).unwrap(), calls)
    }

    #[test]
    fn eof_and_blank_do_not_mutate_or_publish() {
        for input in ["", "6", "\n0\n", "13\n", "13\nTWITCH", "13\nyes\n0\n"] {
            let (_, calls) = drive(input, "idle");
            assert!(calls
                .iter()
                .all(|(name, args)| ["status", "routes"].contains(&name.as_str())
                    && args == &json!({})));
        }
    }

    #[test]
    fn default_start_is_only_recording_and_never_retried() {
        let (_, calls) = drive("6\n0\n", "idle");
        let starts: Vec<_> = calls.iter().filter(|(name, _)| name == "start").collect();
        assert_eq!(starts.len(), 1);
        assert_eq!(starts[0].1, json!({"output":"recording"}));
    }

    #[test]
    fn twitch_requires_separate_menu_and_full_word() {
        let (_, calls) = drive("13\nTWITCH\n0\n", "idle");
        assert_eq!(
            calls
                .iter()
                .filter(|(name, args)| name == "start" && args == &json!({"output":"twitch"}))
                .count(),
            1
        );
    }

    #[test]
    fn unknown_route_cannot_be_built() {
        let (output, calls) = drive("3\nraw-mic-to-local\n0\n", "idle");
        assert!(output.contains("Unknown selection"));
        assert!(!calls
            .iter()
            .any(|(name, args)| name == "routes" && args.get("settings").is_some()));
    }

    #[test]
    fn no_route_save_while_running() {
        let (output, calls) = drive("3\n0\n", "running");
        assert!(output.contains("Idle"));
        assert!(!calls
            .iter()
            .any(|(name, args)| name == "routes" && args.get("settings").is_some()));
    }

    #[test]
    fn source_selection_sends_only_strict_patch() {
        let (_, calls) = drive("3\n1\n1\n0\n", "idle");
        assert!(calls.contains(&(
            "routes".into(),
            json!({"settings":{"capture":{"target":"DP-1"}}})
        )));
    }

    #[test]
    fn malicious_device_display_is_escaped_and_cannot_be_selected() {
        let mut output = Vec::new();
        let mut saved = false;
        run_with(Cursor::new("3\n1\n1\n0\n"), &mut output, |command, args| {
            if command == "routes" && args != "{}" {
                saved = true;
            }
            let answer = if command == "devices" {
                json!({"local":{"role":"capture","gsr_targets":["DP-1\u{1b}[2J\nFORGED"]}})
            } else {
                fixture(command)
            };
            Ok(answer.to_string())
        })
        .unwrap();
        let text = String::from_utf8(output).unwrap();
        assert!(!text.contains('\u{1b}'));
        assert!(!text.contains("\nFORGED"));
        assert!(!saved);
    }

    #[test]
    fn route_table_uses_server_routes_not_an_invented_graph() {
        let (output, _) = drive("0\n", "idle");
        assert!(output.contains("game.av"));
        assert!(output.contains("capture.gpu -> transport.rtmp"));
        assert!(output.contains("local.headphones, obs.game"));
    }

    #[test]
    fn eof_inside_selection_does_not_save() {
        for input in ["3\n", "3\n1\n", "3\n1\n1"] {
            let (_, calls) = drive(input, "idle");
            assert!(!calls
                .iter()
                .any(|(name, args)| name == "routes" && args.get("settings").is_some()));
        }
    }

    #[test]
    fn state_is_rechecked_after_selection_before_saving() {
        let mut status_calls = 0;
        let mut saved = false;
        let mut output = Vec::new();
        run_with(Cursor::new("3\n1\n1\n0\n"), &mut output, |command, args| {
            let mut answer = fixture(command);
            if command == "status" {
                status_calls += 1;
                if status_calls >= 3 {
                    answer["state"] = json!("running");
                }
            }
            if command == "routes" && args != "{}" {
                saved = true;
            }
            Ok(answer.to_string())
        })
        .unwrap();
        assert!(!saved);
        assert!(String::from_utf8(output).unwrap().contains("Stop first"));
    }

    #[test]
    fn discovery_escapes_malicious_labels_without_terminal_controls() {
        let mut output = Vec::new();
        run_with(Cursor::new("2\n0\n"), &mut output, |command, _| {
            let mut answer = fixture(command);
            if command == "devices" {
                answer["local"]["sources"][0]["description"] = json!("Raw\u{1b}[2J\nFAKE\u{202e}");
            }
            Ok(answer.to_string())
        })
        .unwrap();
        let text = String::from_utf8(output).unwrap();
        assert!(text.contains("\\u{1b}[2J\\nFAKE\\u{202e}"));
        assert!(!text.contains('\u{1b}'));
        assert!(!text.contains('\u{202e}'));
    }

    #[test]
    fn exact_app_selection_excludes_tts() {
        let mut calls = Vec::new();
        run_with(Cursor::new("3\n2\n1\n0\n"), Vec::new(), |command, args| {
            calls.push((
                command.to_owned(),
                serde_json::from_str::<Value>(args).unwrap(),
            ));
            let answer = if command == "devices" {
                json!({"local":{"role":"capture","audio_apps":["SplitCast-TTS","osu!"]}})
            } else {
                fixture(command)
            };
            Ok(answer.to_string())
        })
        .unwrap();
        assert!(calls.contains(&(
            "routes".into(),
            json!({"settings":{"capture":{"game_audio":"app:osu!"}}})
        )));
    }

    #[test]
    fn raw_mic_selection_excludes_monitors_and_processed_sources() {
        let mut calls = Vec::new();
        run_with(Cursor::new("3\n3\n1\n0\n"), Vec::new(), |command, args| {
            calls.push((command.to_owned(), serde_json::from_str::<Value>(args).unwrap()));
            let answer = if command == "devices" {
                json!({"local":{"role":"capture","sources":[{"name":"monitor"},{"name":"easyeffects_source"},{"name":"rnnoise_source"},{"name":"splitcast_mic"},{"name":"alsa_input.usb"}]}})
            } else { fixture(command) };
            Ok(answer.to_string())
        }).unwrap();
        assert!(calls.contains(&(
            "routes".into(),
            json!({"settings":{"audio":{"mic_source":"alsa_input.usb"}}})
        )));
    }

    #[test]
    fn failed_recording_does_not_retry_or_echo_transport_secrets() {
        let mut starts = 0;
        let mut output = Vec::new();
        run_with(Cursor::new("6\n0\n"), &mut output, |command, _| {
            if command == "start" {
                starts += 1;
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "Bearer TOP_SECRET_TOKEN",
                ));
            }
            Ok(fixture(command).to_string())
        })
        .unwrap();
        assert_eq!(starts, 1);
        let text = String::from_utf8(output).unwrap();
        assert!(text.contains("No automatic retry"));
        assert!(!text.contains("TOP_SECRET_TOKEN"));
    }
}
