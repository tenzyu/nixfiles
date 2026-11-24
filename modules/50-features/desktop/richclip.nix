{
  flake.modules.homeManager.richclip = {
    config,
    lib,
    pkgs,
    ...
  }: let
    richclip = pkgs.unstable.callPackage ../../../assets/packages/richclip.nix {};
    # Keep the menu on the ordinary socket. Only the upstream capture/restore
    # daemon needs Jay's privileged Wayland data-control connection.
    picker = pkgs.writeShellApplication {
      name = "richclip-picker";
      runtimeInputs = [richclip pkgs.jq pkgs.tofi];
      text = ''
        items="$(richclip list --json)"
        rows="$(printf '%s\n' "$items" | jq -r '.[] | .id + " " + ((.label // (.formats | map(.mime) | join(", "))) | gsub("[\\r\\n\\t]"; " "))')"
        [ -n "$rows" ] || exit 0
        selection="$(printf '%s\n' "$rows" | tofi --require-match=true)" || exit 0
        [ -n "$selection" ] || exit 0
        id="''${selection%% *}"
        printf '%s\n' "$items" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null
        richclip restore "$id"
      '';
    };
  in {
    config = lib.mkIf config.local.features.richclip.enable {
      home.packages = [richclip picker];
    };
  };
}
