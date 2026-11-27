{pkgs}: let
  inherit (pkgs) lib;
  nodejs = pkgs.nodejs_24;
  common = {
    inherit nodejs;
    npmInstallFlags = ["--ignore-scripts"];
    npmRebuildFlags = ["--ignore-scripts"];
    npmPackFlags = ["--ignore-scripts"];
    PUPPETEER_SKIP_DOWNLOAD = "true";
    DESKTOP_COMMANDER_DISABLE_TELEMETRY = "1";
    DC_FLAG_URL = "data:application/json,%7B%22flags%22%3A%7B%7D%7D";
  };
  desktopCommander = pkgs.buildNpmPackage (common // {
    pname = "desktop-commander";
    version = "0.3.4";
    src = pkgs.fetchurl {
      name = "desktop-commander-0.3.4.tar.gz";
      url = "https://codeload.github.com/wonderwhy-er/DesktopCommanderMCP/tar.gz/9a101b17e44577f0baefa4c7120f087881c5cc56";
      hash = "sha256-KwUKrGfjMP05kp3aI3LcSsBFXCTY2gBpr63XZB2F/wQ=";
    };
    patches = [./zod-migrate.patch];
    postPatch = ''
      cp --no-preserve=mode ${./desktop-commander/package.json} package.json
      cp --no-preserve=mode ${./desktop-commander/package-lock.json} package-lock.json
    '';
    preBuild = ''
      substituteInPlace src/tools/pdf/markdown.ts \
        --replace-fail 'async function getChromePath(): Promise<string | undefined> {' \
          "async function getChromePath(): Promise<string | undefined> { if (process.platform === 'linux') return '${pkgs.chromium}/bin/chromium';"
    '';
    npmDepsHash = "sha256-I/xokRNzauiGm0+kq4LxjR2mgWI0lYu+ybUn84pEQJU=";
    makeWrapperArgs = [
      "--prefix" "PATH" ":" (lib.makeBinPath [pkgs.ripgrep pkgs.bash pkgs.coreutils])
      "--set" "DESKTOP_COMMANDER_DISABLE_TELEMETRY" "1"
      "--set" "DC_FLAG_URL" common.DC_FLAG_URL
      "--set" "PUPPETEER_SKIP_DOWNLOAD" "true"
    ];
    postBuild = ''
      node test/test-mcp-tool-input-schemas.js
      node test/integration/read-file-unknown-params.js
    '';
    meta.mainProgram = "desktop-commander";
  });
  supergateway = pkgs.buildNpmPackage (common // {
    pname = "supergateway";
    version = "4.3.0";
    src = ./supergateway;
    npmDepsHash = "sha256-SdZZrSEetc0rbklxel0MKvw+hIDw81eaZPJLnz/8hY4=";
    dontNpmBuild = true;
    nativeBuildInputs = [pkgs.makeWrapper];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/remote-execution-mcp" "$out/bin"
      cp -a node_modules "$out/lib/remote-execution-mcp/"
      cp ${./probe.mjs} "$out/lib/remote-execution-mcp/probe.mjs"
      makeWrapper "$out/lib/remote-execution-mcp/node_modules/.bin/supergateway" "$out/bin/supergateway"
      makeWrapper ${nodejs}/bin/node "$out/bin/remote-execution-mcp-probe" \
        --add-flags "$out/lib/remote-execution-mcp/probe.mjs"
      runHook postInstall
    '';
    meta.mainProgram = "supergateway";
  });
in {
  inherit desktopCommander supergateway;
}
