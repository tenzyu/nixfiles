{...}: {
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = 2283;
    openFirewall = false;
    mediaLocation = "/var/lib/immich";
    # Baseline CPU-only service; enable ML/GPU in a reviewed guest release
    # after actual resource availability and device parity are verified.
    machine-learning.enable = false;
    accelerationDevices = [];
    database.enable = true;
    redis.enable = true;
  };
}
