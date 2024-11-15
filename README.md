# Dotfiles (with chezmoi)
私のコンフィグの一部

## chezmoi の範囲外でやらないといけないこと
リンク先の内容が変わってしまうとアレなので、一応転記していく\
パッケージのダウンロードとかはそのうち script を書くので省略

### XDG Base Directory
https://wiki.archlinux.org/title/XDG_Base_Directory \
https://wiki.archlinux.org/title/Environment_variables#Using_pam_env \
`/etc/security/pam_env.conf`
```
XDG_DATA_HOME DEFAULT=@{HOME}/.local/share
XDG_CONFIG_HOME DEFAULT=@{HOME}/.config
XDG_STATE_HOME DEFAULT=@{HOME}/.local/state
XDG_CACHE_HOME DEFAULT=@{HOME}/.cache
```

### zsh
Move the file to "$XDG_CONFIG_HOME"/zsh/.zshrc and export the following environment variable:
```
export ZDOTDIR="$XDG_CONFIG_HOME"/zsh
```
You can do this in /etc/zshenv (Or /etc/zsh/zshenv, on some distros).

### ccache
https://wiki.archlinux.org/title/Ccache#Enable_ccache_for_makepkg

2.1 Enable ccache for makepkg\
To enable ccache when using [makepkg](https://wiki.archlinux.org/title/Makepkg) edit `/etc/makepkg.conf`. In `BUILDENV` uncomment `ccache` (remove the exclamation mark) to enable caching. For example:\
/etc/makepkg.conf
```
BUILDENV=(!distcc color ccache check !sign)
```

## Trouble Shooting

### bat が tokyonight_night を見つけられない
.cache を削除したときとかになる
```
bat cache --build
```
