#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/packages/splitcast-web/dist}"
target="${CARGO_TARGET_DIR:-$root/packages/splitcast-web/target}"
cargo build --manifest-path "$root/packages/splitcast-web/Cargo.toml" --locked --release --target wasm32-unknown-unknown
mkdir -p "$out"
cp "$root/packages/splitcast-web/assets/index.html" "$root/packages/splitcast-web/assets/loader.js" "$out/"
wasm-bindgen --target web --out-dir "$out" --out-name splitcast_web "$target/wasm32-unknown-unknown/release/splitcast_web.wasm"
