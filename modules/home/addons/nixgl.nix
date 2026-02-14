{inputs, ...}: {
  nixGL.packages = inputs.nixgl.packages;
  nixGL.vulkan.enable = true;
  nixGL.defaultWrapper = "mesa";
  nixGL.installScripts = [
    "mesa"
  ];
}
