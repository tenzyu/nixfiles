use serde_json::{json, Map, Value};
use std::io;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Output {
    Recording,
    Twitch,
}

impl Output {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Recording => "recording",
            Self::Twitch => "twitch",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MicAction {
    Status,
    Mute,
    Unmute,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TtsAction {
    Status,
    On,
    Off,
    Mute,
    Unmute,
    Skip,
    Clear,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Command {
    Status,
    Heartbeat,
    Doctor,
    Devices { remote: bool },
    Prepare,
    Start(Output),
    Stop,
    Routes { settings: Option<Value> },
    Mic(MicAction),
    Tts(TtsAction),
    Say { text: String, id: Option<String> },
    Overlay { text: String },
    Preview,
    Diagnostics,
    TtsNext,
    TtsAck { id: String },
    TtsFinished { id: String },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Invocation {
    pub command: Command,
    pub owner: Option<OwnerId>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OwnerId(String);
impl OwnerId {
    pub fn parse(owner: &str) -> io::Result<Self> {
        if owner.is_empty() || owner.len() > 128 || owner.chars().any(char::is_control) {
            Err(invalid())
        } else {
            Ok(Self(owner.to_owned()))
        }
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

fn invalid() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        "unknown or invalid command arguments",
    )
}
pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
}

fn string<'a>(args: &'a Map<String, Value>, name: &str) -> io::Result<&'a str> {
    args.get(name).and_then(Value::as_str).ok_or_else(invalid)
}
fn action<'a>(args: &'a Map<String, Value>) -> io::Result<&'a str> {
    if args.contains_key("action") {
        string(args, "action")
    } else {
        Ok("status")
    }
}

impl Invocation {
    pub fn from_body(body: &str, max_text: usize) -> io::Result<Self> {
        if body.len() > 16384 {
            return Err(invalid());
        }
        let value: Value = serde_json::from_str(body).map_err(|_| invalid())?;
        let object = value.as_object().ok_or_else(invalid)?;
        if object.len() != 2 || !object.contains_key("command") || !object.contains_key("args") {
            return Err(invalid());
        }
        Self::parse(string(object, "command")?, &value["args"], max_text)
    }
    pub fn parse(name: &str, args: &Value, max_text: usize) -> io::Result<Self> {
        let args = args.as_object().ok_or_else(invalid)?;
        let allowed: &[&str] = match name {
            "status" | "heartbeat" | "doctor" | "prepare" | "stop" | "preview" | "diagnostics"
            | "tts-next" => &[],
            "devices" => &["remote"],
            "start" => &["output"],
            "routes" => &["settings"],
            "mic" | "tts" => &["action"],
            "say" => &["text", "id"],
            "overlay" => &["text"],
            "tts-ack" | "tts-finished" => &["id"],
            _ => return Err(invalid()),
        };
        if args
            .keys()
            .any(|k| k != "_owner" && !allowed.contains(&k.as_str()))
        {
            return Err(invalid());
        }
        let owner = if args.contains_key("_owner") {
            let owner = string(args, "_owner")?;
            if owner.is_empty() || owner.len() > 128 || owner.chars().any(char::is_control) {
                return Err(invalid());
            }
            Some(OwnerId::parse(owner)?)
        } else {
            None
        };
        let text = |limit: usize, empty: bool| -> io::Result<String> {
            let text = string(args, "text")?;
            if (!empty && text.trim().is_empty())
                || text.chars().count() > limit
                || text
                    .chars()
                    .any(|c| c.is_control() && c != '\n' && c != '\t')
            {
                return Err(invalid());
            }
            Ok(text.to_owned())
        };
        let id = || -> io::Result<String> {
            let id = string(args, "id")?;
            if !valid_id(id) {
                return Err(invalid());
            }
            Ok(id.to_owned())
        };
        let command = match name {
            "status" => Command::Status,
            "heartbeat" => Command::Heartbeat,
            "doctor" => Command::Doctor,
            "devices" => Command::Devices {
                remote: match args.get("remote") {
                    Some(v) => v.as_bool().ok_or_else(invalid)?,
                    None => true,
                },
            },
            "prepare" => Command::Prepare,
            "stop" => Command::Stop,
            "start" => Command::Start(
                match args
                    .get("output")
                    .map(|v| v.as_str().ok_or_else(invalid))
                    .transpose()?
                    .unwrap_or("recording")
                {
                    "recording" => Output::Recording,
                    "twitch" => Output::Twitch,
                    _ => return Err(invalid()),
                },
            ),
            "routes" => Command::Routes {
                settings: match args.get("settings") {
                    Some(v) if v.is_object() => Some(v.clone()),
                    Some(_) => return Err(invalid()),
                    None => None,
                },
            },
            "mic" => Command::Mic(match action(args)? {
                "status" => MicAction::Status,
                "mute" => MicAction::Mute,
                "unmute" => MicAction::Unmute,
                _ => return Err(invalid()),
            }),
            "tts" => Command::Tts(match action(args)? {
                "status" => TtsAction::Status,
                "on" => TtsAction::On,
                "off" => TtsAction::Off,
                "mute" => TtsAction::Mute,
                "unmute" => TtsAction::Unmute,
                "skip" => TtsAction::Skip,
                "clear" => TtsAction::Clear,
                _ => return Err(invalid()),
            }),
            "say" => Command::Say {
                text: text(max_text, false)?,
                id: if args.contains_key("id") {
                    Some(id()?)
                } else {
                    None
                },
            },
            "overlay" => Command::Overlay {
                text: text(1000, true)?,
            },
            "preview" => Command::Preview,
            "diagnostics" => Command::Diagnostics,
            "tts-next" => Command::TtsNext,
            "tts-ack" => Command::TtsAck { id: id()? },
            "tts-finished" => Command::TtsFinished { id: id()? },
            _ => return Err(invalid()),
        };
        Ok(Self { command, owner })
    }
    pub fn to_body(&self) -> String {
        let (name, mut args) = self.command.request();
        if let Some(owner) = &self.owner {
            args.as_object_mut()
                .unwrap()
                .insert("_owner".into(), json!(owner.as_str()));
        }
        json!({"command":name,"args":args}).to_string()
    }
}

impl Command {
    pub fn request(&self) -> (&'static str, Value) {
        match self {
            Self::Status => ("status", json!({})),
            Self::Heartbeat => ("heartbeat", json!({})),
            Self::Doctor => ("doctor", json!({})),
            Self::Devices { remote } => ("devices", json!({"remote":remote})),
            Self::Prepare => ("prepare", json!({})),
            Self::Start(output) => ("start", json!({"output":output.as_str()})),
            Self::Stop => ("stop", json!({})),
            Self::Routes { settings } => (
                "routes",
                settings
                    .as_ref()
                    .map(|s| json!({"settings":s}))
                    .unwrap_or_else(|| json!({})),
            ),
            Self::Mic(action) => (
                "mic",
                json!({"action":match action{MicAction::Status=>"status",MicAction::Mute=>"mute",MicAction::Unmute=>"unmute"}}),
            ),
            Self::Tts(action) => (
                "tts",
                json!({"action":match action{TtsAction::Status=>"status",TtsAction::On=>"on",TtsAction::Off=>"off",TtsAction::Mute=>"mute",TtsAction::Unmute=>"unmute",TtsAction::Skip=>"skip",TtsAction::Clear=>"clear"}}),
            ),
            Self::Say { text, id } => ("say", {
                let mut v = json!({"text":text});
                if let Some(id) = id {
                    v["id"] = json!(id);
                }
                v
            }),
            Self::Overlay { text } => ("overlay", json!({"text":text})),
            Self::Preview => ("preview", json!({})),
            Self::Diagnostics => ("diagnostics", json!({})),
            Self::TtsNext => ("tts-next", json!({})),
            Self::TtsAck { id } => ("tts-ack", json!({"id":id})),
            Self::TtsFinished { id } => ("tts-finished", json!({"id":id})),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn default_start_never_publishes() {
        assert_eq!(
            Invocation::parse("start", &json!({}), 200).unwrap().command,
            Command::Start(Output::Recording)
        );
        assert!(Invocation::parse("start", &json!({"output":false}), 200).is_err());
    }
    #[test]
    fn rejects_unknown_args_and_ambiguous_body() {
        for body in [
            r#"{"command":"status","args":{"extra":true}}"#,
            r#"{"command":"status","args":null}"#,
            r#"{"command":"status","args":{},"token":"hidden"}"#,
            r#"{} {}"#,
        ] {
            assert!(Invocation::from_body(body, 200).is_err());
        }
    }
    #[test]
    fn text_roundtrips_without_losing_quotes_or_whitespace() {
        let original = Invocation {
            command: Command::Overlay {
                text: " \"quoted\"\n日本語 ".into(),
            },
            owner: None,
        };
        assert_eq!(
            Invocation::from_body(&original.to_body(), 200).unwrap(),
            original
        );
    }
}
