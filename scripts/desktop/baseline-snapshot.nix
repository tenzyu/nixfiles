# Read-only snapshot for comparing two source revisions. No activation/build.
{flakeRef}: let
  f = builtins.getFlake flakeRef;
  inherit (f.inputs.nixpkgs) lib;
  host = f.nixosConfigurations.neko5.config;
  snapshot = s: let
    h = s.home-manager.users.tenzyu;
    epp = s.systemd.services.neko5-hwp-epp;
  in {
    policy = {
      inherit (s.boot) kernelParams;
      inherit (s.powerManagement) cpuFreqGovernor;
      inherit (s.services.udev) extraRules;
      epp = {
        inherit (epp) script after wantedBy;
        inherit (epp.serviceConfig) Type;
      };
      rate = s.services.pipewire.extraConfig.pipewire."90-neko5-rate";
      pulseRt = s.services.pipewire.extraConfig.pipewire-pulse."90-neko5-rtkit";
      alsa = s.services.pipewire.wireplumber.extraConfig."90-neko5-alc257-lowlatency";
      clientRt = h.xdg.configFile."pipewire/client.conf.d/90-neko5-rtkit.conf".text;
      quantum = h.xdg.configFile."pipewire/client.conf.d/90-neko5-osu-quantum.conf".text;
      rtkit = s.security.rtkit.enable;
      systemState = s.system.stateVersion;
      homeState = h.home.stateVersion;
      inherit (h.home) homeDirectory;
      homeRoutes = map (r: {inherit (r) group source target route;}) h.local.homeMigration.paths;
      mime = h.xdg.mimeApps.defaultApplications;
      skinXml = h.xdg.dataFile."mime/packages/osu-skin.xml".text;
      mimeActivation = h.home.activation.updateLocalMimeDatabase;
      portal = s.xdg.portal.config;
    };
    homePackages = map lib.getName h.home.packages;
    homePackageDrvs = map (p: p.drvPath) h.home.packages;
  };
in {
  result = {
    jay = host.home-manager.users.tenzyu.xdg.configFile."jay/config.toml".text;
    primary = snapshot host;
    probe = snapshot host.specialisation.neko5-gamescope.configuration;
  };
}
