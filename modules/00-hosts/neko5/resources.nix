{
  configurations.nixos.neko5.module = {
    # 2026-11-25: 7.69 GiB empty zram still owns ~30.83 MiB of metadata.
    # Halve the logical capacity, not the compression ratio; keep LZ4,
    # priority 100, physical swap, oomd and all VM watermarks unchanged.
    # This applies to the normal workstation and its independent DRM probe.
    zramSwap.memoryPercent = 25;

    # Preserve allocinfo during resource research. Try page-flag tag storage
    # rather than the observed ~29.75 MiB page_ext allocation. Physical boot
    # must report mem_profiling=1 AND mem_profiling_compressed=1; otherwise
    # reject this parameter independently. No kernel rebuild or cache trick.
    boot.kernelParams = ["sysctl.vm.mem_profiling=1,compressed"];
  };
}
