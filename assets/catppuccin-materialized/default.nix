# Generated sources are ordinary hashed inputs, not imported Nix build outputs.
# A changed upstream derivation falls back to the original package.
{lib, upstream}: let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
  upstream // lib.mapAttrs (name: receipt: let
    original = upstream.${name};
  in
    if original.drvPath == receipt.drvPath
    then builtins.path {
      path = ./data + "/${name}";
      inherit name;
      sha256 = receipt.narHash;
    }
    else original
  ) (builtins.intersectAttrs upstream manifest)
