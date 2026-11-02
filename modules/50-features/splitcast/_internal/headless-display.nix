{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.splitcast-display;
  xorgConfig = pkgs.writeText "splitcast-xorg.conf" ''
    Section "ServerFlags"
      Option "AutoAddDevices" "false"
      Option "AutoAddGPU" "false"
    EndSection
    Section "Files"
      ModulePath "${config.hardware.nvidia.package.bin}/lib/xorg/modules"
      ModulePath "${pkgs.xorg-server}/lib/xorg/modules"
    EndSection
    Section "Device"
      Identifier "SplitCastGPU"
      Driver "nvidia"
      Option "AllowEmptyInitialConfiguration" "true"
      Option "UseDisplayDevice" "None"
    EndSection
    Section "Screen"
      Identifier "SplitCastScreen"
      Device "SplitCastGPU"
      DefaultDepth 24
      SubSection "Display"
        Depth 24
        Virtual 1920 1080
      EndSubSection
    EndSection
  '';
  auth = "/run/splitcast-display/Xauthority";
in {
  options.services.splitcast-display = {
    enable = lib.mkEnableOption "an isolated, manually started NVIDIA Xorg display for SplitCast";
    user = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Existing user allowed to read the display's Xauthority cookie.";
    };
    display = lib.mkOption {
      type = lib.types.ints.between 1 255;
      default = 99;
      description = "Isolated X11 display number. TCP listening is disabled.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.local.features.splitcast-production.enable;
        message = "splitcast-display requires the splitcast-production NixOS feature.";
      }
      {
        assertion = cfg.user != "" && builtins.hasAttr cfg.user config.users.users;
        message = "splitcast-display.user must name an existing user.";
      }
      {
        assertion = lib.elem "nvidia" config.services.xserver.videoDrivers;
        message = "splitcast-display requires the NVIDIA driver.";
      }
    ];
    systemd.services.splitcast-display = {
      description = "Isolated SplitCast NVIDIA Xorg display";
      after = ["systemd-udev-settle.service"];
      wantedBy = [];
      startLimitIntervalSec = 60;
      startLimitBurst = 3;
      preStart = ''
        ${pkgs.coreutils}/bin/touch ${auth}
        ${pkgs.coreutils}/bin/chmod 0600 ${auth}
        ${pkgs.xauth}/bin/xauth -f ${auth} add :${toString cfg.display} . "$(${pkgs.util-linux}/bin/mcookie)"
        ${pkgs.coreutils}/bin/chown ${lib.escapeShellArg cfg.user} ${auth}
      '';
      serviceConfig = {
        ExecStart = "${pkgs.xorg-server}/bin/Xorg :${toString cfg.display} -config ${xorgConfig} -auth ${auth} -nolisten tcp -noreset -novtswitch -logfile /run/splitcast-display/Xorg.log";
        RuntimeDirectory = "splitcast-display";
        RuntimeDirectoryMode = "0711";
        KillMode = "control-group";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
      };
    };
  };
}
