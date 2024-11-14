# Dotfiles (with chezmoi)
私のコンフィグの一部

## chezmoi の範囲外でやらないといけないこと
リンク先の内容が変わってしまうとアレなので、一応転記していく
パッケージのダウンロードとかはそのうち script を書くので省略

### ccache
https://wiki.archlinux.org/title/Ccache#Enable_ccache_for_makepkg

2.1 Enable ccache for makepkg
To enable ccache when using [makepkg](https://wiki.archlinux.org/title/Makepkg) edit `/etc/makepkg.conf`. In `BUILDENV` uncomment `ccache` (remove the exclamation mark) to enable caching. For example:
/etc/makepkg.conf
```
BUILDENV=(!distcc color ccache check !sign)
```
