# SplitCast browser client

Build with Rust 1.95, its `wasm32-unknown-unknown` standard library, `lld`, and `wasm-bindgen-cli` 0.2.121. Run `bash scripts/build-web.sh` from the repository root. Pass an output directory as the first argument to override `packages/splitcast-web/dist`.

The loopback service must serve the generated files at the same origin as `/api/command`, including the WASM MIME type `application/wasm`. Its content security policy must permit same-origin scripts, WASM compilation, and connections. The baseline service does not serve these files. Do not expose the service on a public interface.

The token remains in page memory and is sent in the Authorization header. Server validation remains authoritative. The baseline `routes` command reports that route editing is not ported; the browser shows that response rather than inventing routes. The route table accepts an array, or an object with a `routes` array, containing string `source`, `processor`, and `target` fields.

The browser client currently serializes the command envelope locally. Replace that code with the shared portable protocol when the service library exports it. The native unit tests do not test a browser, the server, or media operations.
