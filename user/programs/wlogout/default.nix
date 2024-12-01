{
  programs.wlogout = {
    enable = true;
    layout = [
      {
        label = "lock";
        text = "Lock";
        keybind = "l";
        action = "sleep 1; hyprlock";
      }
      {
        label = "hibernate";
        text = "Hibernate";
        keybind = "h";
        action = "sleep 1; systemctl hibernate";
      }
      {
        label = "logout";
        text = "Exit";
        keybind = "e";
        action = "sleep 1; loginctl terminate-user $USER";
      }
      {
        label = "shutdown";
        text = "Shutdown";
        keybind = "s";
        action = "sleep 1; systemctl poweroff";
      }
      {
        label = "suspend";
        text = "Suspend";
        keybind = "u";
        action = "sleep 1; systemctl suspend";
      }
      {
        label = "reboot";
        text = "Reboot";
        keybind = "r";
        action = "sleep 1; systemctl reboot";
      }
    ];
  };
}
