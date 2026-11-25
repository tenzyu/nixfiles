{
  flake.modules.homeManager.mako = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # Local single-provider policy: unlike upstream's generic notifier package,
    # neko5 selects Mako as its sole notification daemon.
    managedMako = pkgs.mako.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        provider="$out/share/dbus-1/services/org.freedesktop.Notifications.service"
        mv "$out/share/dbus-1/services/fr.emersion.mako.service" "$provider"
        printf '%s\n' 'SystemdService=mako.service' >> "$provider"
      '';
    });
  in {
    config = lib.mkIf config.local.features.mako.enable {
      # HM services.mako ordinarily installs the package twice: once through
      # home.packages (user profile) and again through dbus.packages
      # (~/.local/share). Keep exactly one activatable service description.
      # package=null retains HM's Mako settings, but skips both installations.
      home.packages = [managedMako];
      services.mako = {
        enable = true;
        package = null;
        settings = {
          anchor = "top-right";
          layer = "top";
          font = "FiraCode Nerd Font 11";
          width = 360;
          height = 120;
          margin = "12";
          padding = "8";
          border-size = 1;
          border-radius = 8;
          max-icon-size = 32;
          icons = true;
          markup = true;
          default-timeout = 5000;
          ignore-timeout = false;

          background-color = "#1e1e2eee";
          text-color = "#cdd6f4ff";
          border-color = "#89b4faff";
          progress-color = "over #313244ff";

          "mode=hyprland-gamemode" = {
            invisible = 1;
          };
          "mode=hyprland-gaming-cli" = {
            invisible = 1;
          };

          "urgency=low" = {
            default-timeout = 3000;
          };

          "urgency=critical" = {
            default-timeout = 0;
            border-color = "#f38ba8ff";
          };
        };
      };
    };
  };
}
