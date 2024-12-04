{pkgs, ...}: {
  nixpkgs.config.permittedInsecurePackages = [
    ### NOTE: for pkgs.opentabletdriver {{{
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-runtime-6.0.36"
    ### }}}
  ];
  home.packages = [pkgs.opentabletdriver];
}
