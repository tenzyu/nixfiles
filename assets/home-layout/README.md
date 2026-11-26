# 既存 HOME データを移行・復旧する

> **運用上の位置付け（2026-11-23）** [ADR-0003](../../docs/adr/0003-home-layout-reuse-first.md) により、HOME の見た目のためだけの新規移行や全域強制は追求しない。この README は **既に main にある移行・復旧機構を使う場合の安全手順**であり、今すぐ移行を実行する指示ではない。コードを撤去するまでは既存のチェック・journal・衝突拒否を維持する。

neko5 の既存 TODO は旧 Home 移行の不具合を記録している。この実装の実機受入は **NOT RUN**。
[移行と復旧の判断](../../docs/memory/decisions.md)

## 調査と holding generation

対象ユーザーの未適用の Home Manager generation から `home-layout-migrate` を実行する。

```sh
generation=$(nix build --no-link --print-out-paths \
	.#nixosConfigurations.neko5.config.home-manager.users.tenzyu.home.activationPackage)
"$generation/home-layout-migrate" inventory
"$generation/home-layout-migrate" check --group codex
```

`inventory` は旧・移行先・候補の実効ルートと、宣言上のシェル／user service 環境を表示する。
稼働中のアプリのルートを、それを起動した shell、GUI、service のルートと照合する。
既存の split や独自ラッパーを見つけた場合は、正しいルートが判明するまで対象の writer を停止する。
初回導入には検証した incumbent を記録する。以下は Codex が旧ルートを使っている場合の例。
feature の選択は `local.users.<user>.features` に置く。

```nix
home-manager.users.tenzyu.local.homeMigration = {
	legacyGroups = ["codex"];
	adoptedRoutes.codex = "legacy";
};
```

`legacyGroups` は旧ルートで継続するグループ。既に意図した保存先を使用しているグループは
初回導入時に `adoptedRoutes.<group> = "intended"` と記録できる。両側が未作成のグループは
意図したルートで開始できる。保存先の計画と現在のルートは別々に評価される。

NixOS の `system.preSwitchChecks` は実現済みの候補と稼働中の generation を照合し、
対象 UID で検査する。実行は bootloader／サービス／per-user package profile の切替より前。
候補と適用済みの両方でルートのないアカウントは、通常の NixOS と Home Manager の処理で作成・更新される。
ルートやアカウントを廃止する場合も適用済みのルートを検査し、データが残る場合や HOME が利用できない場合は切替を保留する。
Home Manager も `checkLinkTargets` と `writeBoundary` の前に保護対象を再確認する。
診断は移行の状態、activation の書き込み、アプリのルートをそれぞれ示す。
旧ルートを保持し書き込みが安全なら、保留中の移行があっても他の設定を適用できる。
XDG base の変更では、候補の両ルートが空でも適用済み generation の宣言と実効ルートを調べる。
適用済みルートにデータが残っていれば、writer の排除と検証済み移行が必要になる。

保護対象の通常ファイル、帰属を証明できないリンク、危険な親リンクは、
強制リンク、旧 generation の cleanup、バックアップ設定があっても上書きしない。
管理ファイルの検査にはビルド済みの具体的な leaf とリンク先を使う。
追加 DAG の書き込みは `local.homeMigration.activationWrites` に監査済みのパスだけを宣言する。
書き込み範囲が不明な hook は、保護対象から分離するまで activation を保留する。
無関係な管理ファイルについては Home Manager 標準の衝突規則が適用される。

## グループと保存先

移行前に [グループと保存先の一覧](groups.md) を確認する。

## 承認された移行ウィンドウ

対象の UID・ホスト・候補 generation・グループ・外部 XDG mount・退避先を確認する。
操作前にバックアップを確保し、復元手順を確認する。
ログインセッション、GUI、user unit、タイマー、自動再起動元、シェル終了時の履歴保存を停止する。メンテナンス環境では mount や親ディレクトリの
差し替えと、対象データへの全 writer を除外する。HOME の `flock` はこの runner 同士を直列化する。
`--offline` は運用上確立した排他の確認であり、プロセス走査で排他を保証するものではない。

```sh
runner="$generation/home-layout-migrate"
"$runner" plan --group codex
"$runner" apply --group codex --offline --expect TOKEN
```

`plan` の `expect` は対象・計画・実行環境を識別する。いずれかが変わった場合は `plan` を再実行する。
`check`、`inventory`、`plan` は読み取り専用。`check --require-noop` は移行の必要なしで
`0`、操作や参照修復の保留で `2`、衝突・不明・検査エラーで `1`。

同じ mount では、payload と親を同期し、既存先を置き換えない rename で移動する。
別 mount では、対象側の private staging へ pinned rsync でコピーし、独立した inventory で
内容、型、所有者、mode、mtime、ACL/xattr、hardlink と symlink を確認する。同期後に対象 mount
内で公開し、旧側を保持する。元のツリー外への hardlink、入れ子の mount、bind の不明点、
特殊ファイル、メタデータ未対応などは個別の計画が必要。tmpfs はテスト用に使えるが再起動で消える。

Home Manager scaffold は実 generation の leaf と参照先、信頼できる祖先、余分な entry の
不在を照合できる場合だけ退避する。同じ mount 上の private 名に保存し、独立した操作として記録する。
両側にデータがあれば通常の `apply` は停止する。違いのある両側は保存し、権限者が
アプリ固有の手順で第三の場所に照合結果を作り、復元可能性を確認する。
照合済みの対象を配置し旧名を可逆的に退避した場合は、その承認を
`local.homeMigration.reconciledGroups` に記録できる。切替時に旧名、対象側、残る参照、session を検査する。

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

## 中断・退避・ロールバック

version 2 の `operations.jsonl` は private な保存先に置く。初回の保存先は
`$XDG_STATE_HOME/home-cleanup/bronze/activation`。承認済み操作で HOME 直下の
`.home-layout-journal-domain.json` に保存先を記録する。後続世代は XDG state base を変更しても、
記録された保存先を参照する。以前の候補が別の XDG state base を使っていた場合は、
`local.homeMigration.legacyStateHomes` にその base を宣言する。過去の journal は元の場所に保持する。

intent は名前空間を変更する前に、完了は両側の親を同期した後に
記録する。新しい apply は未完了の run があれば停止する。排他を確立し直し、同じ generation と
group の runner に表示された run ID を渡す。

```sh
"$runner" recover --group GROUP --offline --run RUN_ID
```

apply、rollback、退避の再開では、グループ全体の元、公開先、staging、退避先の記録と実物を、
未完了の先行操作が作るパスも含めて確認してから journal とファイルを更新する。公開済みで完了記録だけが
欠ける場合は identity と内容を再検証して続行する。中断した staging は保持し、新しい staging
を作る。再開前に、新たに staging が必要なコピーの容量を対象ファイルシステムごとに合計して確認する。
検証済みの staging と公開済みのコピーは追加容量に含めず、新しい staging の作成直前にも空き容量を検査する。
矛盾、破損記録、旧版 journal、mount identity の変化は現物とバックアップを照合して
別途対応する。旧版 journal を退ける場合も証拠を保持し、修復後のルートを再検証する。

`retire --group GROUP --offline --run RUN_ID` は検証済み cross-mount 移行の旧側を可逆退避する。
退避開始時と復旧時は、完了した転送 journal から権限を確認し、公開先、残っている旧側、
退避先、既に完了した操作をグループ全体で照合してから次の操作に進む。identity や内容が
記録と異なる場合は、追加の退避を始めずに現存するデータを保全する。
既に同等に見える二つのコピーには、採用先への承認を得て別途の `plan --group GROUP --retire-equal`
と `retire-equal --group GROUP --offline --expect TOKEN` を使う。いずれも通常 apply と別の承認が必要。
`rollback --group GROUP --offline --run RUN_ID` は検証できた移動や退避を逆順に戻す。
新しいルートで書き込みが始まった後、または旧名が再作成された場合は両方を保全し、再照合する。
Nix generation の rollback にデータの復元は含まれない。退避データの削除は別の承認まで保留する。

## 切替と検証

個別に承認された切替では、排他を維持したまま対象 group を `legacyGroups` から外した候補を
検査・適用する。認識できない手動 reconciliation、check の bypass、古い generation の直接 boot、
HOME を利用できない場合は、writer を戻す前に offline の手順で回復する。切替の成否に応じて
current、booted、Nix profile の generation を別々に記録する。

セッションと user manager を更新し、通常の起動経路と子プロセスの実効ルート、旧レコードの
読み込み・保存・再起動後の読み込み、旧パスの再生成有無を確認する。稼働中のプロセスの
環境は設定のビルドでは変わらない。retirement が保留中ならその状態も記録する。

```sh
nix build --no-link -L .#checks.x86_64-linux.home-migration
nix build -L --no-link .#checks.x86_64-linux.framework
```

Home check は packaged runner の故障試験と、使い捨て NixOS VM の native switch／embedded HM を実行する。
VM のデータは fixture 専用。アプリの環境・保存の流れは fixture adapter で確認する。
物理ホスト、認証、実アプリ、ハードウェアは別途検証する。
