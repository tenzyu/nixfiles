{
  flake.modules.homeManager.mako = {
    services.mako = {
      enable = true;
      settings = {
        anchor = "top-right";
        layer = "overlay";
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
}
