{
  programs.tmux = {
    enable = true;

    # 使い勝手
    shortcut = "j";
    keyMode = "vi";
    mouse = true;
    historyLimit = 50000;
    escapeTime = 0;
    baseIndex = 1; # pane の開始番号
    clock24 = true;
    newSession = true;
    terminal = "tmux-256color";
    customPaneNavigationAndResize = true; # Vim っぽく pane 移動

    extraConfig = ''
      # 分割キーを人間向けにする
      unbind '"'
      unbind %
      bind | split-window -h
      bind - split-window -v

      # 見た目ちょい整理
      set -g status-position bottom
      set -g renumber-windows on
      set -g set-clipboard on
    '';
  };
}
