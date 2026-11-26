{
  ark = {
    key = "ark";
    user = "game-ark";
    uid = 27007;
    gid = 27007;
    home = "/var/lib/game-containers/ark";
    gameDir = "/srv/ark";
    containerName = "neko7-ark";
    guestService = "ark-survival-evolved";
    backupSource = "server/ShooterGame/Saved";
    hostAddress = "10.77.10.1";
    localAddress = "10.77.10.2";
    tailscaleHostname = "neko7-ark";

    udpPorts = [
      7777
      7778
      27015
    ];

    tcpPorts = [
      # ARK RCON / optional browser RCON UI.
      # Tailscale policy should expose these to owner/admin only.
      27020
      4326
      4327
    ];
  };

  rust = {
    key = "rust";
    user = "game-rust";
    uid = 27008;
    gid = 27008;
    home = "/var/lib/game-containers/rust";
    gameDir = "/srv/rust";
    containerName = "neko7-rust";
    guestService = "rust-dedicated";
    backupSource = "server/server";
    hostAddress = "10.77.20.1";
    localAddress = "10.77.20.2";
    tailscaleHostname = "neko7-rust";

    udpPorts = [
      # Rust game / query.
      28015
      28017
    ];

    tcpPorts = [
      # Rust RCON / Rust+.
      # Tailscale policy should expose these to owner/admin only.
      28016
      28082
    ];
  };
}
