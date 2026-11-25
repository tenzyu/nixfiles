{
  configurations.nixos.neko5.module = {config, ...}: {
    # Empty 7.69 GiB zram had ~30.83 MiB of slot metadata. Use a compressed
    # cache of the existing NVMe swap instead: zswap creates entries on demand,
    # not one zram table slot for every logical page. No double compression.
    # Swap capacity is now bounded by the physical partition (~7.45 GiB).
    # Reject this candidate if real workload capacity or latency regresses.
    zramSwap.enable = false;

    # Linux >=6.18 no longer has the zpool parameter. Use native kernel
    # arguments rather than the pinned NixOS zswap module's legacy zpool
    # setting. Zstd is the stock nixpkgs kernel's configured compressor.
    # No custom kernel build for an already-supported mechanism.
    boot.kernelParams = [
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.max_pool_percent=25"
      "zswap.shrinker_enabled=1"

      # Allocation provenance has already been captured. Avoid the observed
      # ~29.75 MiB page_ext overhead and profiling hot-path instrumentation.
      # '0' at runtime cannot release boot-time metadata. Re-enable at boot
      # with sysctl.vm.mem_profiling=1 for a separate diagnostic session.
      "sysctl.vm.mem_profiling=never"
    ];

    assertions = [{
      assertion = config.swapDevices != [];
      message = "neko5 zswap requires its existing physical swap device.";
    }];
    # Retain memory cgroups, oomd, all reclaim watermarks, CPU count,
    # preemption, driver parameters and thermal/security mitigations.
  };
}
