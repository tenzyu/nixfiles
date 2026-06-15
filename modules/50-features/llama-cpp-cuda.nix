{
  flake.effects.llama-cpp-cuda = {
    requires = ["nvidia-graphics"];

    system = {
      collect.pkgs.unfreePackages = [
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
    };
  };

  flake.modules.nixos.llama-cpp-cuda = {pkgs, ...}: {
    environment.systemPackages = [
      (pkgs.llama-cpp.override {cudaSupport = true;})
    ];
  };
}
