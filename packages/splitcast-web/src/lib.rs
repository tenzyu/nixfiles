use serde_json::{json, Value};

pub fn command(name: &str, args: Value) -> String {
    json!({"command": name, "args": args}).to_string()
}

pub fn start_command() -> String {
    command("start", json!({"output": "recording"}))
}

pub fn twitch_command(confirmed: bool) -> Option<String> {
    confirmed.then(|| command("start", json!({"output": "twitch"})))
}

pub fn parse_response(text: &str) -> Result<Value, serde_json::Error> {
    serde_json::from_str(text)
}

#[cfg(target_arch = "wasm32")]
mod browser;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn start_defaults_to_recording() {
        let value = parse_response(&start_command()).unwrap();
        assert_eq!(value["command"], "start");
        assert_eq!(value["args"]["output"], "recording");
    }

    #[test]
    fn parse_server_response() {
        assert_eq!(
            parse_response(r#"{"status":"idle"}"#).unwrap()["status"],
            "idle"
        );
        assert!(parse_response("not json").is_err());
    }

    #[test]
    fn twitch_requires_confirmation() {
        assert!(twitch_command(false).is_none());
        let request = parse_response(&twitch_command(true).unwrap()).unwrap();
        assert_eq!(request["args"]["output"], "twitch");
    }
}
