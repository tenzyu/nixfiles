{...}: {
  flake.modules.homeManager.herdr = {
    config,
    lib,
    pkgs,
    ...
  }: let
    stock = pkgs.llm-agents.herdr;
    # Herdr 0.9.5 has no OSC 52 preference setting (upstream #6035).
    # Reuse its existing fallback without changing its compiled derivation.
    # Only the exact native copy call from the stock Herdr executable on
    # Jay is rejected; other wl-copy callers retain their normal behavior.
    clipboardFallback = pkgs.writeShellScriptBin "wl-copy" (lib.replaceStrings
      ["@HERDR@" "@WL_COPY@" "@READLINK@"]
      ["${stock}/bin/herdr" "${pkgs.wl-clipboard}/bin/wl-copy" "${pkgs.coreutils}/bin/readlink"]
      (builtins.readFile ../../../scripts/desktop/herdr-wl-copy.sh));
    jayHerdr = pkgs.symlinkJoin {
      name = "${stock.name}-jay";
      inherit (stock) pname version meta;
      paths = [stock];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram "$out/bin/herdr" --prefix PATH : ${clipboardFallback}/bin
      '';
      passthru.unwrapped = stock;
    };
  in {
    config = lib.mkIf config.local.features.herdr.enable {
      home.packages = [(
        if config.local.features.jay.enable
        then jayHerdr
        else stock
      )];
    };
  };
}
