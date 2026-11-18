# Host-local cache policy for enabled SplitCast consumer roles.
# A release tag may differ from the flake rev; verify actual store paths.
{
  extra-substituters = [
    "https://github.com/tenzyu/splitcast/releases/download/nix-cache-d2205d06b0dc695c3d9b7372fafa7facee769fa9-43561723796-1"
  ];
  extra-trusted-public-keys = [
    "splitcast-1:vTbhAaBTWjRfVHQekUUYwSb9GBftwHNgBUhXGk0jGwM="
  ];
}
