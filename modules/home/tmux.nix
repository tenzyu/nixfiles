{
  flake.modules.homeManager.tmux = {
    programs.tmux = {
      enable = true;

      # 使い勝手
      shortcut = "j";
      keyMode = "vi";
      mouse = true;
      focusEvents = true;
      historyLimit = 50000;
      escapeTime = 0;
      baseIndex = 1; # pane の開始番号
      clock24 = true;
      newSession = true;
      terminal = "tmux-256color";
      customPaneNavigationAndResize = true; # Vim っぽく pane 移動

      extraConfig = ''
        set -g detach-on-destroy off
        set -g status-position bottom
        set -g renumber-windows on
        set -g set-clipboard on
        bind c new-window -c "#{pane_current_path}"

        # 分割キーを人間向けにする
        unbind '"'
        unbind %
        bind h split-window -h -c "#{pane_current_path}"
        bind v split-window -v -c "#{pane_current_path}"

        # prefix + Enter で縦分割したシェルに戻る
        bind Enter split-window -v -c "#{pane_current_path}"

        # よく使うセッション導線
        bind-key C-a last-window
        bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "tmux config reloaded"
        bind-key g new-window -n git -c "#{pane_current_path}" "lazygit"
        bind-key A command-prompt -p "session name" "new-session -A -s '%%'"

        # copy mode を terminal-first 向けに寄せる
        bind-key -T copy-mode-vi v send-keys -X begin-selection
        bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
        bind-key -T copy-mode-vi Escape send-keys -X cancel
      '';
    };
  };
}
