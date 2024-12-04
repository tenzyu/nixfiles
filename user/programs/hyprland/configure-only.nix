{
  home.file.".config/hypr/hyprland.conf".source = ./hyprland.conf;
  home.file.".config/hypr/hyprland.conf.d".source = ./hyprland.conf.d;

  # Todo: withUWSM flag
  #   programs.zsh.profileExtra = ''
  #     if uwsm check may-start && uwsm select; then
  #       exec systemd-cat -t uwsm_start uwsm start default
  #     fi
  #   '';
}
