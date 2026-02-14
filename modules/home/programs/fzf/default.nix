{pkgs, ...}: let
  myDefaultCommand = "${pkgs.fd}/bin/fd --hidden --strip-cwd-prefix --exclude .git";
in {
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

    defaultCommand = myDefaultCommand;

    fileWidgetCommand = myDefaultCommand;
    fileWidgetOptions = [
      "--preview '${pkgs.bat}/bin/bat -n --color=always --line-range :500 {}'"
    ];

    changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type=d --hidden --strip-cwd-prefix --exclude .git";
    changeDirWidgetOptions = [
      "--preview '${pkgs.eza}/bin/eza --tree --color=always {} | head -200'"
    ];
  };
}
