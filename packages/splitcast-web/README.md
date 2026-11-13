# SplitCast browser client

Build with Rust 1.95, its `wasm32-unknown-unknown` standard library, `lld`, and `wasm-bindgen-cli` 0.2.121. Run `bash scripts/build-web.sh` from the repository root. Pass an output directory as the first argument to override `packages/splitcast-web/dist`.

The Nix package supplies generated assets to the loopback agent through `SPLITCAST_WEB_ASSETS`. The server permits only fixed asset paths and serves WASM as `application/wasm`. Its content security policy permits same-origin scripts, WASM compilation and connections. Do not expose the service on a public interface.

The token remains in page memory and is sent in the Authorization header. Server validation remains authoritative. The route table displays the source and finite processor and target arrays returned by the server. It does not invent an editable graph.

The browser and TUI use `splitcast-protocol` for the command model. Browser rendering and operation logic are Rust. The handwritten loader only initializes generated WASM glue. The native unit tests do not establish live browser or media operation.
