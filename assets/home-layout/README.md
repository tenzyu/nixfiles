# XDG home layout / 既存ホームの移行

保存先の宣言と既存データの移行は一組。`home-layout` だけでなく、保存先を変える
`common` / `zsh` / `firefox` がそれぞれ `local.homeMigration.paths` を宣言する。
実行部分は `modules/50-features/home-migration.nix` と `migrate.py`。
ユーザー名、ホスト名、固定の `.config` / `.local/share` を実装に埋め込まない。

## 初めて別マシンへ適用する

対象ホストで設定をビルドし、そのホストのホームを所有するユーザーで実行する。
例は neko7。`home-layout` が必要なら、ホストの user features に明示的に追加する。
neko7 の既存 feature 選択そのものは本変更では変更していない。

```sh
generation=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.neko7.config.home-manager.users.tenzyu.home.activationPackage)
"$generation/home-layout-migrate" check
# 対象アプリと旧環境のシェルを終了。古いシェルは終了時にも履歴を書き戻す。
"$generation/home-layout-migrate" apply
sudo nixos-rebuild switch --flake .#neko7
```

`check` は読み取り専用。移動計画または衝突パスを表示する。
初回は switch **前**に `apply` し、移行後から switch 完了までは対象アプリを起動しない。
これにより NixOS が先に per-user profile を切り替える時間帯も避けられる。
Home Manager activation 自体にも同じ検査・移行があり、通常の再適用は自動で処理する。
ビルドだけでは実ホームは変更されない。

新しいシェル・再ログイン後に環境変数、認証・履歴・プロファイル、旧パスの再生成を確認する。
既に動作中の GUI 親プロセスや旧 shell の環境を Nix が遡及的に書き換えるわけではない。

## 移行規則

| feature | 旧パス → 新しい保存先 |
|---|---|
| home-layout | `.codex` → `$CODEX_HOME`、`.gemini` → `$GEMINI_CLI_HOME/.gemini` |
| home-layout | `.bun/install/cache` → `$BUN_INSTALL_CACHE_DIR`、残りの `.bun` → `$BUN_INSTALL` |
| home-layout | `.bash_history` → `$XDG_STATE_HOME/bash/history` |
| home-layout | `.claude` → `$CLAUDE_CONFIG_DIR`、`.claude.json` → その中の `.claude.json` |
| home-layout + android-mic | `.android` → `$ANDROID_USER_HOME/.android`（adb 限定 HOME ラッパーと対） |
| firefox | `.mozilla/firefox` → `programs.firefox.configPath` |
| common | `.cargo` / `.rustup` / `go` → 対応する XDG data root |
| common | `.npm` / `.nuget/packages` → 対応する XDG cache root |
| common | `.npm-init.js` / `.gtkrc-2.0` → 対応する XDG config path |
| common | `.node_repl_history` → XDG state、`.dotnet` → `$DOTNET_CLI_HOME/.dotnet` |
| zsh | `.zsh_history` → `programs.zsh.history.path` |

Gemini と .NET の環境変数は、隠しディレクトリ自身でなくその**親**を指す。
adb の鍵は `ANDROID_USER_HOME` だけでは移らないため、ラッパーが有効なときだけ移す。
Bun の `bin` も保持し、新パスを session PATH に加える。
`common` の保存先変数は systemd user environment にも同じ値を宣言する。

## 動作の契約

- 旧パスなし：何もしない。完了マーカーではなく、毎回パスの状態から判定する。
- 旧パスのみ：同一 FS 内の `renameat2(RENAME_NOREPLACE)` で移動。
  内容・inode・所有者・パーミッションを維持し、別 FS のコピーへ暗黙に切り替えない。
- 新旧に実データあり：**全移動の前に停止**。新旧の優劣を時刻や容量だけで決めない。
  空の通常ファイルや内容が同じファイルも、自動上書きの対象にはしない。
- 新側がディレクトリと Nix store symlink だけ：生成 scaffold として専用の状態ディレクトリへ
  退避してから旧ツリーを移す。実データのツリーマージはしない。
- HM が新パスで管理するファイルが旧データに存在：store link 以外なら停止。
  特に独自 `profiles.ini` / `user.js` は内容を見ずに HM の default へ置き換えない。
  Firefox の profile 名・path はホストの HM 定義と照合して明示的に解決する。
- 旧ツリー自身や親が symlink、移動で意味が変わる相対リンク、旧ルートへの絶対リンク：停止。
- 対象プロセスの名前・実行ファイル・先頭の argv を `/proc` で検査する。
  `.adb-wrapped` と Node 経由の CLI も含む。移行のないアプリは稼働していてもよい。
- Codex の `config.toml` / `hooks.json` の自己ルート参照だけを、バックアップを残して更新。
  移動後の再実行でも補修できる。任意の設定・セッション履歴へ再帰的な置換はしない。
- `DRY_RUN` 時は検査のみ。実移動は HM の `writeBoundary` 後、`linkGeneration` /
  `installPackages` 前。移動で出現するファイルの将来の HM 衝突も事前検査する。

移行記録・生成物の退避・参照編集前のコピーは
`$XDG_STATE_HOME/home-cleanup/bronze/activation/<run>/`。自動削除しない。
intent と完了を JSONL に記録する。全体は単一トランザクションではないが、
途中停止後は既に終わった rename を繰り返さず、未完了分を再検査して続行する。

## 衝突・ロールバック

両方に実データがある場合は対象を閉じ、独立したバックアップを取り、アプリ固有の
認証・履歴・DB・profile を比較して採用先を決める。新側を機械的に消して再実行しない。
判断済みの片方を private state へ退避した後、`check` → `apply` → switch をやり直す。

Nix generation の rollback は**データの rename を戻さない**。旧設定へ戻すと旧パスに
新データができ得る。アプリを閉じ、JSONL の完了済み移動を逆順に見て、旧パスが
不在なことを確認して戻す。参照編集は記録された backup と対応づけて戻す。
中断時は intent だけで成功とみなさず、両パスの実在・inode を確認する。

## 自動化の境界

プロセス検査はアプリの排他ロックや system 全体のトランザクションではない。
サービスの自動再起動、sandbox 内の別 adb、旧シェルの履歴書き戻し、任意の外部設定に
埋まった絶対パスまでは一般に保証できない。初回は対象を止めて移行し、再ログイン後も確認する。
Rust/Bun/.NET の手動インストールを外部の固定 PATH やラッパーから参照している場合も
その参照を点検する。新たな保存先変数を追加する際は、読み手・書き手と移行規則を同時に追加する。

neko5 で行った Projects 移設、旧 proxy 分解、未使用アプリや Pulse cookie の退避は
個別に内容を確認した作業であり、他ホストへ自動再生する規則ではない。
`.pki`（旧 CEF/NSS が再生成）、`.agents`、`.storybook`、`.zed_server`、`.zshenv` などは
利用するソフトウェアの固定パス／共有運用に基づく例外。単純移動で消した扱いにしない。

## 検証

```sh
nix build .#checks.x86_64-linux.home-migration
```

fixture home で認証ファイル保持、再実行、nested Claude JSON、Bun cache 分離、Firefox
scaffold と実データ衝突、将来の HM 衝突、symlink、別 FS、中断後の再開などを検証する。
実ホームの activation や認証付きアプリの起動をテストから実行しない。
