{...}: {
  flake.modules.nixos.nix = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.nix.enable {
      nix = {
        package = pkgs.nixVersions.stable;
        settings = {
          use-xdg-base-directories = true;
          extra-experimental-features = [
            "nix-command"
            "flakes"
          ];
          accept-flake-config = true;
          auto-optimise-store = true;

          extra-substituters = [
            "https://nix-community.cachix.org"
            "https://cache.nixos-cuda.org"
            "https://cache.numtide.com"
            "https://github.com/tenzyu/splitcast/releases/download/nix-cache-d2205d06b0dc695c3d9b7372fafa7facee769fa9-43561723796-1"
          ];
          extra-trusted-public-keys = [
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
            "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
            "splitcast-1:vTbhAaBTWjRfVHQekUUYwSb9GBftwHNgBUhXGk0jGwM="
          ];
        };
        gc = {
          automatic = true;
          options = "--delete-older-than 7d";
        };
      };
    };
  };
}
