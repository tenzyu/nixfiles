# HOME 移行のグループと保存先

| group | 所有 feature | 旧パスと意図した保存先 |
|---|---|---|
| `rust` | common | `.cargo`, `.rustup` → XDG data、Cargo bin も PATH に反映 |
| `go` | common | `go/` → XDG data。既存の明示的な GOBIN/GOMODCACHE は独立した保存先 |
| `npm` | common | `.npm`, `.npm-init.js` → XDG cache/config。npm runtime scratch に移動対象なし |
| `node-history`, `gtk2` | common | Node REPL 履歴 → XDG state、GTK2 rc → XDG config |
| `dotnet` | common | `.nuget/packages` → XDG cache、`.dotnet` → `$DOTNET_CLI_HOME/.dotnet` |
| `codex`, `gemini` | home-layout | `.codex` → `$CODEX_HOME`、`.gemini` → `$GEMINI_CLI_HOME/.gemini` |
| `bun` | home-layout | Bun cache を先に分離し、残りの `.bun` → XDG data。Bun bin も PATH に反映 |
| `claude` | home-layout | `.claude` と `.claude.json` → XDG config の同じツリー。旧ルート保持時は CLAUDE_CONFIG_DIR を設定しない |
| `bash-history`, `zsh` | home-layout / zsh | Bash と Zsh 履歴 → XDG state。Zsh は native `history.path` を使用 |
| `firefox` | firefox | `.mozilla/firefox` → managed Firefox wrapper の `configPath` |
| `android-mic` | android-mic + home-layout | `.android` → `$ANDROID_USER_HOME/.android`。adb の HOME と FHS 内 PATH は同じラッパーを使用 |

`common` と `home-layout` の環境設定は手動で導入したツールにも使える。例えば Codex の
パッケージ feature が false でも `home-layout` が選択されていれば Codex のルートを扱う。
Parsec の `.parsec` はこの移行の範囲外。

[移行と復旧の手順](README.md) を参照する。
