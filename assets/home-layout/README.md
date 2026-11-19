# XDG home layout / 既存ホームの移行

> **2026-11-17 documentation reconciliation:** `neko5` enables `home-layout` but still contains a TODO reporting migration bugs. The procedure below describes the implementation contract; acceptance on the current real home was **not** verified here. See [safety decisions](../../docs/decisions.md).


## 移行の明示承認と activation の安全ゲート

Home Manager の移行ステップは `check --activation` による読み取り専用の検査。
保留中の移動・手動修復だけなら、feature、操作、旧パス、移動先、確認手順を警告して
activation を続ける。両側の実データ、将来の管理ファイルとの衝突、不正なパス、未対応の
ファイルシステムや検査エラーは、原因を表示して `writeBoundary` より前に停止する。
次の Home Manager 標準 `checkLinkTargets` は、現在の管理ファイルとの衝突を独立して検査する。
警告後にアプリを起動すると新しい保存先にデータができ得るため、必要な移行はアプリ起動前に確認する。

```sh
generation=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.neko5.config.home-manager.users.tenzyu.home.activationPackage)
"$generation/home-layout-migrate" check
```

バックアップ、停止プロセス、対象パス、衝突、ロールバックを確認した後、別途の人間の承認を得て、対象ホストで `home-layout-migrate apply` を明示的に実行する。通常の `nixos-rebuild switch` や Home Manager activation ではデータを移動しない。

保存先の宣言と既存データの移行は一組。`home-layout` だけでなく、保存先を変える
`common` / `zsh` / `firefox` がそれぞれ `local.homeMigration.paths` を宣言する。
実行部分は `modules/50-features/home/home-migration.nix` と `migrate.py`。
`android-mic` が adb ラッパー、環境変数、移行規則を所有し、任意の XDG レイアウトは両 feature が
有効なときに選ぶ。`home-layout` は個別のパッケージ feature から導入していないアプリにも使う、
明示的な保存先プロファイル。例えば neko5 は `codex.enable = false` で、`CODEX_HOME` は
`home-layout` を選択したシェルのために存続する。無効な所有 feature の規則は含めず、旧パスを
使ったことのないアプリや移行済みのアプリは通常無操作となる。
ユーザー名、ホスト名、固定の `.config` / `.local/share` を実装に埋め込まない。
ローカル Python エンジンとネイティブ Home Manager を使い、xdg-ninja は診断に限る。

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

`check` は読み取り専用。移動計画または衝突パスを表示する。`check --require-noop` は
計画が空なら `0`、移動や人手による修復が必要なら `2`、衝突や検査エラーなら `1` を返す。
修復が必要と表示された場合は、先に下の「既存リンクと参照の修復」を参照する。
初回は switch **前**に `apply` し、移行後から switch 完了までは対象アプリを起動しない。
これにより NixOS が先に per-user profile を切り替える時間帯も避けられる。
Home Manager activation 自体にも同じ読み取り専用の事前検査があるが、移行の自動実行はない。
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
| android-mic（home-layout も有効な場合） | `.android` → `$ANDROID_USER_HOME/.android`（adb 限定 HOME ラッパーと対） |
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
- 新旧に実データあり：どちらも残して全移動の前に停止する。Bun/npm の `onConflict = "backup"`
  は廃止。旧キャッシュの再生成可能性から退避の権限を推定しない。
- 手動の `check` は、同じ mount 内の読み取れる通常ファイルとディレクトリについて、ツリー、
  全バイト、型・UID/GID・モード・mtime・xattr を比較する。シンボリックリンク、ハードリンク、
  特殊ファイル、別 mount、読めない entry、検査中に変化した entry は同等と判断しない。
  変化を観測できなくても他の writer を排除できないため、結果は「見かけ上一致」にとどまり、
  同じ内容でも移動や削除を許可しない。activation と apply では全データの比較を行わない。
- 生成 scaffold は、現在有効な Home Manager 管理先にある generation link とその祖先だけの、
  実行 UID 所有の標準モードで xattr のないツリーに限定する。通常ファイル、任意の store link、
  空ディレクトリだけのツリーはこの例外の対象外。明示的な apply は scaffold を検査し直し、
  専用の状態ディレクトリに inode ごと退避する。この退避は旧データを移す rename とは別操作。
- HM が新パスで管理するファイルが旧データに存在：store link 以外なら停止。
  特に独自 `profiles.ini` / `user.js` は内容を見ずに HM の default へ置き換えない。
  Firefox の profile 名・path はホストの HM 定義と照合して明示的に解決する。
- 旧ツリー自身や移動に使う親が symlink、移動で意味が変わる相対リンクは停止。
  `repairAbsoluteLinks = true` は旧ルートへの絶対リンクの修復案を `check` に表示する。
  入れ子の移行は最も具体的な旧ルートを優先する。既に移動済みのツリーも検査する。
- 対象プロセスの名前・実行ファイル・先頭の argv を `/proc` で検査する。
  `.adb-wrapped` と Node 経由の CLI も含む。移行のないアプリは稼働していてもよい。
- Codex の `config.toml` / `hooks.json` の旧ルート参照を検出し、修復案の JSON/TOML を
  検証する。診断にはファイルの場所を表示する。
- Home Manager activation の `check --activation` は `checkLinkTargets` と `writeBoundary` の前に
  実行する。プロセスの稼働だけで activation を妨げず、手動の check/apply は writer の警告を
  維持する。実移動は独立した `home-layout-migrate apply` の実行時だけ。

移行記録と移行先の退避は `$XDG_STATE_HOME/home-cleanup/bronze/activation/<run>/` に残る。
旧版が作った `references/` のコピーも復旧資料として保管する。

## 既存リンクと参照の修復

**人間によるレビューが必要。** 現在の構成では既存リンクや参照ファイルへの排他所有を
立証できない。`symlink` または `rewrite` が必要な batch は、`apply` が state や journal を
作る前に拒否する。以前は Bun リンクの置換と Codex 参照のバックアップ付き書き換えを行い、
先行する移動の中断後にも修復できた。現在は移動前と移動済みの両方で同じ診断が出る。
通常の移動、既に正しい参照やリンク、条件を満たす Firefox scaffold の退避は続けられる。

[Bun のキャッシュ設定](https://bun.sh/docs/pm/global-cache)と `BUN_INSTALL` は今後の保存先を
指定する。既存キャッシュやプロジェクトの絶対リンクはそのまま残る。
[Bun の global store](https://bun.sh/docs/pm/global-store) を使うプロジェクトはその cache
を直接参照し得る。オフライン依存、global install、外部リンクの要否を先に調べる。
再生成可能なキャッシュなら、元のディレクトリを保持し、承認後に影響するプロジェクトを
Bun の通常のインストールで新しい保存先に再生成できる。
[Codex の設定レイヤー](https://learn.chatgpt.com/docs/config-file/config-basic) と
[hooks](https://learn.chatgpt.com/docs/hooks) の対象に合えば、プロジェクト固有設定はその
プロジェクトに置ける。`CODEX_HOME` は設定の読む場所を選ぶ。既存ファイル本文の任意の
絶対パスやシェルコマンドは、フィールドごとの仕様に沿って人が確認する。
汎用 launcher や互換 symlink は外部 writer を排除できず、旧保存先への依存も残る。

1. `check` の `current` は現在の修復対象、`target` は移動後の位置。対象アプリや旧シェルを
   停止し、他の writer が動かないことを確認して、元のリンク先や参照ファイルを独立した
   バックアップに残す。旧版の途中停止が疑われる場合は先に下の復旧手順で照合する。
2. Bun のリンク案 `replacement` は **移動後のリンク親** を基準とする相対パス。
   移動前に直す場合は、その親で解決した最終の絶対パスを使える。移動完了まではリンク先が
   未作成の場合がある。すでに移動済みなら、表示された親を基準に案を確認する。
3. Codex は対象ファイル内の旧ルート参照だけを、該当ルールの移動先へ更新する。
   宣言から供給されるリンクなら宣言元を修正する。JSON/TOML、パーミッション、無関係な設定を確認する。
4. `check` を再実行し、修復案が消えたことと残る移動を確認する。移動は別途承認した `apply` で行う。

## 衝突・ロールバック

両方に実データがある場合、対象を閉じ、独立したバックアップを取り、認証・履歴・DB・
profile と外部参照を比較して採用先を決める。選ばなかった側は、書き手を止めた上で、
既存 entry のない private な同一ファイルシステム上の保管先へ別途承認して退避する。
新側を採用した場合は `check` が旧パス不在を確認する。旧側を採用した場合は
`check` で予定を確認し、残る move を明示的に `apply` する。旧版の `conflicts/` は復旧資料として保持する。

Nix generation の rollback は**データの rename を戻さない**。旧設定へ戻すと旧パスに
新データができ得る。アプリを閉じ、実物と照合できた移動を逆順に見て、旧パスが不在なことを
確認してから個別に復元を承認する。旧版の参照編集は記録されたバックアップと照合する。

### 中断後の照合

`operations.jsonl` の `move-intent` は rename 前に fsync する。各 rename が成功すると
移動先の親、次に異なる移動元の親を fsync し、その後で `move` を記録して fsync する。
`scaffolding` の退避と `legacy` の移動は独立した rename。旧版の `conflicts` 記録も
同じ復旧手順で照合する。

| 観測 | 復旧時の判断 |
|---|---|
| intent なし、元の entry が残っている | run や空の親が作られただけの場合がある。記録が欠けていれば関連するパスも照合する。 |
| intent あり、記録と一致する元の entry が残り、先に該当 entry がない | 意図は記録されたが rename の成立は観測されていない。衝突や書き手を解消して新たに plan を取る。 |
| intent あり、先に記録と一致する entry が存在、元に該当 entry がない | rename は観測できる。完了記録がなければ親の fsync や完了ログの成否は不明。現存する entry を保全してから復旧を判断する。 |
| backup のみ成立、旧データは元に残っている | backup の内容と inode を確認して保持する。未移動の旧データは再度 `check` の対象になる。 |
| 完了記録と実物が食い違う、両方またはどちらにも対応する entry がない | entry を削除・上書きせず、元・先・backup と独立バックアップを比較して人間が判断する。 |

読み取り専用で、各パスを最終 symlink をたどらずに確認する。記録の device・inode・type と
実データ、mode を照合する。再起動や再マウントで device 番号が変わり得るので、番号だけで判断しない。
途中行や旧形式の JSONL、完了記録、空の plan だけで復旧済みと判断しない。`apply` は現状から
新たに計画を作り、過去の intent を再生しない。照合が済んでから再試行を承認する。

## 自動化の境界

`apply` は Linux で HOME の所有者が実行し、既存 HOME ディレクトリの inode に `flock` を
保持する。同じ HOME を使うこの版の実行同士を直列化する。`check` はロックを取らない。
アプリ、同じ UID の別ツール、旧版の runner、特権プロセスはこのロックの対象外。
source や退避候補の差し替え、親の移動、mount の変更、データへの書き込みを運用側で止める必要がある。
プロセス検査と inode 再検査は診断であり、その排他を確立するものではない。dirfd は開いた
ディレクトリを指し続けるため、運用側で移動される可能性がある名前空間は対象外。

親は `/` から `O_NOFOLLOW` で辿り、root または実行 UID 所有かつ group/other に書き込みを
許さないものを使う。`/tmp` のような sticky ディレクトリは所有者を確認できる既存の子への
経由だけに使う。state は実行 UID 所有の private ディレクトリ。適用範囲は `ext4`、`xfs`、
`btrfs`、`tmpfs` 上の同一 mount・同一 device の rename。移動・退避対象自体やその配下の mount、
別 mount の bind alias、symlink 経由の親、ネットワーク/overlay FS は対象外。`tmpfs` は再起動で消える。
新しいディレクトリは作成時に親を fsync する。既存の祖先と payload の事前の永続化を前提とし、
実行中の予期しない I/O エラーや kernel 拒否では先行分が成立している場合がある。検証は
rename/flush の順序と見える entry を扱う。電源断や各 FS の実機受入は別途行う。

Rust/Bun/.NET の手動インストールを外部の固定 PATH やラッパーから参照している場合も
その参照を点検する。新たな保存先変数を追加する際は、読み手・書き手と移行規則を同時に追加する。

neko5 で行った Projects 移設、旧 proxy 分解、未使用アプリや Pulse cookie の退避は
個別に内容を確認した作業であり、他ホストへ自動再生する規則ではない。
`.pki`（旧 CEF/NSS が再生成）、`.agents`、`.storybook`、`.zed_server`、`.zshenv` などは
利用するソフトウェアの固定パス／共有運用に基づく例外。単純移動で消した扱いにしない。

## 検証

```sh
nix build .#checks.x86_64-linux.home-migration
bash assets/home-layout/test-activation.sh
```

packaged runner と fixture home で認証ファイル保持、再実行、nested Claude JSON、Bun/npm
キャッシュ衝突の拒否、見かけ上一致の保全、Firefox scaffold、将来の HM 衝突、
既存リンク・参照修復時の batch 拒否を検証する。
競合する移動先、別 mount、intent/rename/親 flush/完了記録の失敗では実物と journal を照合する。
Nix sandbox で `/` の所有 UID がマップされない場合、fixture process 内でその所有判定だけを
模擬する。別 process の packaged launcher は読み取り専用で起動し、未対応の親で apply が拒否されることを確認する。
実ホームの activation や認証付きアプリの起動をテストから実行しない。
