{flakeRef}: let
  f = builtins.getFlake flakeRef;
  inherit (f.inputs.nixpkgs) lib;
  c = f.nixosConfigurations.neko5.config;
  h = c.home-manager.users.tenzyu;
  audioRulePath = "pipewire/client.conf.d/90-neko5-osu-quantum.conf";
  clientRtPath = "pipewire/client.conf.d/90-neko5-rtkit.conf";
  rtArgs = { "rtportal.enabled" = false; "rtkit.enabled" = true; };

  routes = home: map (r: { inherit (r) group source target route; }) home.local.homeMigration.paths;
  check = compositor: s:
    let
      sh = s.home-manager.users.tenzyu;
      audio = s.services.pipewire.extraConfig;
      rate = audio.pipewire."90-neko5-rate"."context.properties";
      rules = builtins.fromJSON sh.xdg.configFile.${audioRulePath}.text;
      clientRt = builtins.fromJSON sh.xdg.configFile.${clientRtPath}.text;
      pulseRt = audio.pipewire-pulse."90-neko5-rtkit";
      alsa = (builtins.head s.services.pipewire.wireplumber.extraConfig."90-neko5-alc257-lowlatency"."monitor.alsa.rules").actions."update-props";
      names = map (p: p.name or "") s.environment.systemPackages;
    in {
      profile = s.local.features.jay.enable == (compositor == "jay") && sh.local.features.jay.enable == (compositor == "jay") && s.local.features.gamescope.enable == (compositor == "gamescope");
      launcher = (builtins.elem "start-jay" names) == (compositor == "jay") && (builtins.elem "start-gamescope" names) == (compositor == "gamescope") && !(builtins.elem "neko5-slim-session" names);
      legacyDesktopDisabled = !s.programs.hyprland.enable && !sh.local.features.waybar.enable && !sh.local.features.hyprpaper.enable && !sh.local.features.neko5-osu-first.enable;
      systemPolicy = s.local.features.neko5-hardware.enable && (builtins.elem "preempt=full" s.boot.kernelParams) && s.powerManagement.cpuFreqGovernor == "powersave" && (s.systemd.services ? neko5-hwp-epp) && s.services.tailscale.enable && s.services.pipewire.enable && s.services.openssh.enable && s.nix.distributedBuilds;
      identity = s.networking.hostName == c.networking.hostName && s.system.stateVersion == c.system.stateVersion && sh.home.stateVersion == h.home.stateVersion && sh.home.homeDirectory == h.home.homeDirectory && routes sh == routes h;
      audio = rate."default.clock.rate" == 48000 && rate."default.clock.allowed-rates" == [48000] && !(audio.pipewire ? "99-neko5-experiment") && !(audio.client ? "90-neko5-osu-quantum") && rules == { "stream.rules" = [{ matches = [{ "node.name" = "alsa_playback.osu!"; }]; actions.update-props."node.max-latency" = "64/48000"; }]; };
      realtime = s.security.rtkit.enable && clientRt == { "module.rt.args" = rtArgs; } && pulseRt == clientRt && !(audio.pipewire ? "90-neko5-rtkit") && !(audio.client ? "90-neko5-rtkit");
      hardwareAudio = alsa."api.alsa.headroom" == 0 && alsa."api.alsa.period-size" == 128 && alsa."api.alsa.period-num" == 3 && !alsa."api.alsa.disable-tsched";
      desktopPackages = let
        pkgs = sh.home.packages;
        has = name: builtins.any (p: lib.getName p == name) pkgs;
        herdr = builtins.filter (p: (p.pname or "") == "herdr") pkgs;
      in !has "cliphist" && !has "grimblast"
        && has "cclip-picker" == (compositor == "jay")
        && has "jay-tofi-actions" == (compositor == "jay")
        && builtins.length herdr == 1
        && (if compositor == "jay"
          then (builtins.head herdr).unwrapped.drvPath == f.nixosConfigurations.neko5.pkgs.llm-agents.herdr.drvPath
          else (builtins.head herdr).drvPath == f.nixosConfigurations.neko5.pkgs.llm-agents.herdr.drvPath);
      drv = s.system.build.toplevel.drvPath;
    };
in {
  result = {
  primary = check "jay" c;
  probe = check "gamescope" c.specialisation.neko5-gamescope.configuration;
  onlyProbe = builtins.attrNames c.specialisation == ["neko5-gamescope"];
  audioIsolated = lib.all (name: let
    otherSystem = f.nixosConfigurations.${name}.config;
    other = otherSystem.home-manager.users.tenzyu;
  in !(builtins.hasAttr audioRulePath other.xdg.configFile)
    && !(builtins.hasAttr clientRtPath other.xdg.configFile)
    && !(otherSystem.services.pipewire.extraConfig.pipewire-pulse ? "90-neko5-rtkit")) ["neko6" "neko7"];
  jay = h.xdg.configFile."jay/config.toml".text;
  skinAssociation = h.xdg.mimeApps.defaultApplications."application/x-osu-skin";
  fileAssociation = h.xdg.mimeApps.defaultApplications."inode/directory";
  alacrittyOsc52 = h.programs.alacritty.settings.terminal.osc52;
  herdrReusesStock = let
    packages = builtins.filter (p: (p.pname or "") == "herdr") h.home.packages;
    stock = f.nixosConfigurations.neko5.pkgs.llm-agents.herdr;
  in builtins.length packages == 1 && (builtins.head packages).unwrapped.drvPath == stock.drvPath;
  };
}
