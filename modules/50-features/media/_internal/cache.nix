# Host-local cache policy for enabled SplitCast consumer roles.
# A release tag may differ from the flake rev; verify actual store paths.
{
  extra-substituters = [
    "https://github.com/tenzyu/splitcast/releases/download/nix-cache-b6fcf1588fec4c42b0e22df58f3bca53c2f51b6f-45916419238-1"
  ];
  extra-trusted-public-keys = [
    "splitcast-1:vTbhAaBTWjRfVHQekUUYwSb9GBftwHNgBUhXGk0jGwM="
  ];
}
