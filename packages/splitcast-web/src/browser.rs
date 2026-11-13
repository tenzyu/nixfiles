use std::{cell::RefCell, rc::Rc};

use serde_json::{json, Value};
use wasm_bindgen::{closure::Closure, prelude::*, JsCast};
use wasm_bindgen_futures::{spawn_local, JsFuture};
use web_sys::{Document, Element, HtmlInputElement, Request, RequestInit, RequestMode, Response};

fn element(doc: &Document, parent: &Element, tag: &str, text: &str) -> Result<Element, JsValue> {
    let node = doc.create_element(tag)?;
    node.set_text_content(Some(text));
    parent.append_child(&node)?;
    Ok(node)
}

fn render_routes(doc: &Document, target: &Element, value: &Value) -> Result<(), JsValue> {
    target.set_text_content(None);
    let routes = value
        .as_array()
        .or_else(|| value.get("routes").and_then(Value::as_array));
    let Some(routes) = routes else {
        element(
            doc,
            target,
            "p",
            value
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("Routes are unavailable from this service."),
        )?;
        return Ok(());
    };
    let table = element(doc, target, "table", "")?;
    let header = element(doc, &table, "tr", "")?;
    for title in ["Source", "Processor", "Target"] {
        element(doc, &header, "th", title)?;
    }
    for route in routes {
        let row = element(doc, &table, "tr", "")?;
        for field in ["source", "processor", "target"] {
            element(
                doc,
                &row,
                "td",
                route.get(field).and_then(Value::as_str).unwrap_or("—"),
            )?;
        }
    }
    Ok(())
}

async fn request(token: &str, body: String) -> Result<Value, JsValue> {
    let init = RequestInit::new();
    init.set_method("POST");
    init.set_mode(RequestMode::SameOrigin);
    init.set_body(&JsValue::from_str(&body));
    let req = Request::new_with_str_and_init("/api/command", &init)?;
    req.headers().set("Content-Type", "application/json")?;
    req.headers()
        .set("Authorization", &format!("Bearer {token}"))?;
    let window = web_sys::window().ok_or("No window")?;
    let response: Response = JsFuture::from(window.fetch_with_request(&req))
        .await?
        .dyn_into()?;
    let ok = response.ok();
    let text = JsFuture::from(response.text()?)
        .await?
        .as_string()
        .ok_or("Invalid response")?;
    let value =
        crate::parse_response(&text).map_err(|_| JsValue::from_str("Invalid JSON response"))?;
    if !ok {
        return Err(JsValue::from_str(
            value
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("Request failed"),
        ));
    }
    Ok(value)
}

#[wasm_bindgen(start)]
pub fn start() -> Result<(), JsValue> {
    let window = web_sys::window().ok_or("No window")?;
    let doc = window.document().ok_or("No document")?;
    let app = doc.get_element_by_id("app").ok_or("Missing app")?;
    app.set_text_content(None);
    element(&doc, &app, "h1", "SplitCast")?;
    let label = element(&doc, &app, "label", "Control token ")?;
    let input: HtmlInputElement = doc.create_element("input")?.dyn_into()?;
    input.set_type("password");
    input.set_autocomplete("off");
    label.append_child(&input)?;
    let connect = element(&doc, &app, "button", "Use token")?;
    let notice = element(
        &doc,
        &app,
        "p",
        "Enter the local control token. It stays in this page's memory.",
    )?;
    let token = Rc::new(RefCell::new(String::new()));
    let on_connect = {
        let token = token.clone();
        let notice = notice.clone();
        Closure::<dyn FnMut()>::new(move || {
            *token.borrow_mut() = input.value();
            input.set_value("");
            notice.set_text_content(Some(if token.borrow().is_empty() {
                "Token cleared."
            } else {
                "Token set for this page."
            }));
        })
    };
    connect.add_event_listener_with_callback("click", on_connect.as_ref().unchecked_ref())?;
    on_connect.forget();
    let status = element(&doc, &app, "pre", "Status not loaded.")?;
    element(&doc, &app, "h2", "Routes")?;
    let routes = element(&doc, &app, "div", "Routes not loaded.")?;
    for (title, name, args) in [
        ("Refresh status", "status", json!({})),
        ("Refresh routes", "routes", json!({})),
        ("Prepare", "prepare", json!({})),
        ("Start recording", "start", json!({"output":"recording"})),
        ("Stop", "stop", json!({})),
        ("Mute mic", "mic", json!({"action":"mute"})),
        ("Unmute mic", "mic", json!({"action":"unmute"})),
        ("Start Twitch", "start", json!({})),
    ] {
        let button = element(&doc, &app, "button", title)?;
        let token = token.clone();
        let status = status.clone();
        let routes = routes.clone();
        let doc = doc.clone();
        let body = if title == "Start recording" {
            crate::start_command()
        } else {
            crate::command(name, args)
        };
        let callback = Closure::<dyn FnMut()>::new(move || {
            let body = if title == "Start Twitch" {
                let confirmed = web_sys::window()
                    .and_then(|w| w.confirm_with_message("Start publishing to Twitch?").ok())
                    .unwrap_or(false);
                let Some(body) = crate::twitch_command(confirmed) else {
                    return;
                };
                body
            } else {
                body.clone()
            };
            let token = token.borrow().clone();
            if token.is_empty() {
                status.set_text_content(Some("Enter a control token first."));
                return;
            }
            let status = status.clone();
            let routes = routes.clone();
            let doc = doc.clone();
            spawn_local(async move {
                match request(&token, body).await {
                    Ok(value) if name == "routes" => {
                        if let Err(e) = render_routes(&doc, &routes, &value) {
                            status.set_text_content(Some(&format!("Error: {e:?}")));
                        }
                    }
                    Ok(value) => status.set_text_content(Some(
                        &serde_json::to_string_pretty(&value).unwrap_or_default(),
                    )),
                    Err(e) => status.set_text_content(Some(&format!(
                        "Request failed: {}",
                        e.as_string().unwrap_or_else(|| "network error".into())
                    ))),
                }
            });
        });
        button.add_event_listener_with_callback("click", callback.as_ref().unchecked_ref())?;
        callback.forget();
    }
    Ok(())
}
