{
  configurations.nixos.neko5.module = {lib, ...}: {
    # The physical i5-10210U is 4C/8T; retain all eight logical CPUs and
    # all existing scheduler, DRM, audio, security and device support.
    # Nixpkgs' generic 384-CPU image and default allocation instrumentation
    # are not necessary on this fixed workstation. No Linux source patch.
    boot.kernelPatches = [{
      name = "neko5-workstation-kconfig";
      patch = null;
      structuredExtraConfig = {
        MAXSMP = lib.mkForce lib.kernel.no;
        NR_CPUS = lib.mkForce (lib.kernel.freeform "8");

        # DAMON_STAT is on by default in Linux 7.3. The observed kdamond.0
        # is continuous telemetry, not necessary memory reclaim. Keep the
        # framework available for explicit diagnostics without auto-start.
        DAMON_STAT_ENABLED_DEFAULT = lib.mkForce lib.kernel.no;
        MEM_ALLOC_PROFILING = lib.mkForce lib.kernel.no;
        MEM_ALLOC_PROFILING_ENABLED_BY_DEFAULT = lib.mkForce (lib.kernel.option lib.kernel.no);
        ZSWAP_COMPRESSOR_DEFAULT_ZSTD = lib.mkForce lib.kernel.no;
        ZSWAP_COMPRESSOR_DEFAULT_LZ4 = lib.mkForce lib.kernel.yes;
      };
    }];

    # Empty zram held ~30.83 MiB of slot metadata. A dynamic compressed
    # cache backed by the existing NVMe swap avoids that up-front table.
    # Swap capacity is now bounded by the physical partition (~7.45 GiB).
    zramSwap.enable = false;
    # Linux >= 6.18 uses zsmalloc directly; the old zpool parameter is gone.
    # Keep LZ4, existing VM watermarks, memory cgroups, oomd and PREEMPT_DYNAMIC.
    boot.kernelParams = [
      # THP was responsible for a likely 66 MiB minimum watermark on three
      # populated zones (512-page pageblocks). Let the allocator use its
      # ordinary automatic watermarks by disabling automatic THP policy.
      # Keep THP compiled in; revert this boot argument if osu! tails regress.
      # No direct min_free_kbytes or lowmem_reserve_ratio modification.
      "transparent_hugepage=never"

      "zswap.enabled=1"
      "zswap.compressor=lz4"
      "zswap.max_pool_percent=25"
      "zswap.shrinker_enabled=1"
    ];

    # 448 active conntrack slab objects were observed. Linux 7.3 defaults
    # to 262144 buckets and max=262144 on this RAM size. Explicit hashsize
    # uses factor 8, retaining the same entry ceiling with 32768 buckets.
    # Retain stateful firewall and Tailscale; verify hash chains under load.
    boot.extraModprobeConfig = ''
      options nf_conntrack hashsize=32768
    '';

    # OpenSSH retains the same authenticated endpoint via native per-connection
    # socket activation; no listener process while idle. Never remove SSH.
    services.openssh.startWhenNeeded = true;

  };
}
