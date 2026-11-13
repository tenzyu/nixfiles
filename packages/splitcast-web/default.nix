{lib,rustPlatform,stdenv,wasm-bindgen-cli,lld}: rustPlatform.buildRustPackage {
  pname = "splitcast-web";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [./Cargo.toml ./Cargo.lock ./src ./assets ../splitcast-protocol];
  };
  sourceRoot = "source/splitcast-web";
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [wasm-bindgen-cli lld];
  buildPhase = ''
    runHook preBuild
    cargo build --locked --offline --release --target wasm32-unknown-unknown
    runHook postBuild
  '';
  checkPhase = ''
    cargo test --locked --offline --target ${stdenv.hostPlatform.rust.rustcTarget}
  '';
  installPhase = ''
    mkdir -p "$out"
    cp assets/index.html assets/loader.js "$out/"
    wasm-bindgen --target web --out-dir "$out" --out-name splitcast_web target/wasm32-unknown-unknown/release/splitcast_web.wasm
  '';
  meta.description = "Rust WASM client for the authenticated SplitCast loopback agent";
}
