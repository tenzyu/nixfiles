{
  flake.modules.nixos.nvidia = {
    lib,
    pkgs,
    local,
    ...
  }: {
    hardware.graphics.enable = true;
    services.xserver.videoDrivers = ["nvidia"];
    hardware.nvidia.open = true; # see the note above

    policy.pkgs.allowUnfreeNames = [
      "nvidia-x11"
      "nvidia-settings"
      "cuda_cccl"
      "cuda_cudart"
      "cuda_nvcc"
      "libcublas"
      "cuda-merged"
      "cuda_cuobjdump"
      "cuda_gdb"
      "cuda_nvdisasm"
      "cuda_nvprune"
      "cuda_cupti"
        "cuda_cuxxfilt"
"cuda_nvml_dev"
         "cuda_nvrtc"

"cuda_nvrtc"
 "cuda_nvtx"
"cuda_profiler_api"
"cuda_sanitizer_api"
"libcufft"
        "libcurand"
         "libcusolver"
"libnvjitlink"
"libcusparse"
"libnpp"

    ];

    # test
    environment.systemPackages = with pkgs; [
      # Override the default llama-cpp package to build it specifically with CUDA support.
      (llama-cpp.override {cudaSupport = true;})
      # Highly recommended: A terminal-based GPU monitoring tool
      nvtopPackages.nvidia
    ];
  };
}
