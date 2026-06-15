# tenzyu's nixfiles

個人用の NixOS / Home Manager 構成です。

`flake.nix` は薄く保ち、実装は `modules/` 配下の小さなモジュールとして登録します。ホストは必要な機能名だけを `local.features` / `local.users.<name>.features` に列挙して合成します。

## 設計方針

- **flake は入口に徹する**  
  `flake.nix` は inputs と flake-parts の起動だけを保ちます。構成ロジックは `modules/` へ寄せます。

- **機能を小さく登録し、ホストで選ぶ**  
  SSH、zsh、Docker、Hyprland、Neovim などは `flake.modules.nixos.<feature>` / `flake.modules.homeManager.<feature>` として登録します。ホスト定義は機能名を列挙するだけです。

- **ホストは部品表として読む**  
  `modules/00-hosts/<host>/configuration.nix` を見れば、そのホストに何が入っているかがリストとして分かります。

- **NixOS と Home Manager の境界を薄い合成層で吸収する**  
  同じ feature キーに対して NixOS 側と Home Manager 側の両方を登録できます。feature は user agnostic に書き、user 固有の情報は host が決めます。

- **package policy は feature の近くで宣言する**  
  unfree / insecure な package の許可は `flake.local.featurePolicies.<feature>` に局所的に書きます。framework が一括で `nixpkgs.config` へ投影します。

- **抽象化しすぎない**  
  role や profile を深く積まず、ホストごとの `features.<name>.enable = true;` 列挙を明示します。

## アーキテクチャ

```text
flake.nix
  inputs + flake-parts

modules/
  10-framework/
    flake-modules.nix     flake.lib / flake.local.featurePolicies / flake.modules オプション定義
    configurations.nix    configurations.nixos / configurations.homeManager 評価 + 内部 materializer
                          (nixosPolicyMaterializerModule, homePolicyMaterializerModule,
                           nixosUserAccountsModule, hmFactoryModule, nixpkgsPolicyModule)
    helpers.nix           flake.lib.helpers (usersWithFeature / mapUsersWithFeature / ...)
    formatter.nix         perSystem formatter
    systems.nix           supported systems
    checks.nix            static checks (deprecated-patterns, feature-name-shape)

  00-hosts/
    neko5/                Hyprland desktop / laptop
    neko6/                NixOS-WSL
    neko7/                server / proxmox-guest

  50-features/
    *.nix                 flake.modules.nixos.* / flake.modules.homeManager.* / flake.local.featurePolicies.*
```

## 命名規約

すべての feature 名と host 向けファイル名は kebab-case に統一します。

- 例: `tenzyu-cli` / `tenzyu-desktop` / `docker-rootless` / `networkmanager-access` / `hyprland-tenzyu` / `nvidia-graphics` / `proxmox-guest`
- 内部 let binding や private な helper 関数名はこの限りではありません。

## 概念

### モジュール registry

`flake.modules.<class>.<feature>` に登録されたモジュールがそのまま host の NixOS / Home Manager に積まれます。

- `flake.modules.nixos.<feature>` — NixOS module として host imports に積まれる
- `flake.modules.homeManager.<feature>` — Home Manager module としてユーザーごとに積まれる

同じ feature キーで両方を定義すると、embedded Home Manager (`useGlobalPkgs = true`) で同じ `<feature>` を有効化したときに両側が束縛されます。

### 機能の有効化

- `local.features.<feature>.enable = true;` — system スコープで feature を有効化
- `local.users.<name>.features.<feature>.enable = true;` — user スコープで feature を有効化

user スコープの feature は NixOS 評価時に `local.users.<name>.features` 経由で embedded Home Manager の `local.features` へ流し込まれます (`enabledFeatures` ヘルパーが `enable = true` のものだけを抽出して `local.features` にマージ)。Home Manager 評価時に参照される payload / policy はこの path を経由して決まります。

### Home Manager 内の identity

Home Manager 評価スコープでは `local.user.{name,email,homeDirectory,stateVersion}` が利用可能です。user 名は `local.users.<name>` のキーと一致します。

### Helpers

`flake.lib.helpers` にホスト向けヘルパーを集約しています。`configurations.nix` の `let` 内で `helpers` として `specialArgs` 経由で全 module に配布されます。

- `usersWithFeature feature cfg` — `cfg.local.users` のうち `<feature>` を有効化しているユーザー
- `userNamesWithFeature feature cfg` — 上記のユーザー名リスト
- `mapUsersWithFeature feature cfg f` — 上記ユーザーへ `f` を適用して `users.users` 形の attrset を返す

### Bundle / bridge

- **bundle feature**: `tenzyu-cli` / `tenzyu-desktop` のように、自分自身は payload を持たず `local.features.<other>.enable = true;` を連鎖して有効化する feature。`flake.modules.nixos.<bundle>` は空でもよく、実体は bundle が立てる `local.features` だけ。
- **bridge module**: `parsec-hyprland` / `steam-hyprland` のように、Hyprland デスクトップ環境で別 feature が必要とする前提 (例: XWayland 経由の起動) を整えるための feature。通常の feature module として書く。

## package policy

`flake.local.featurePolicies.<feature>.{unfree, permittedInsecure}` に package 名を列挙します。

```nix
{
  flake.local.featurePolicies.parsec.unfree = ["parsec-bin"];

  flake.modules.nixos.parsec = {config, lib, ...}: {
    config = lib.mkIf config.local.features.parsec.enable {};
  };

  flake.modules.homeManager.parsec = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.parsec.enable {
      home.packages = [pkgs.unstable.parsec-bin];
    };
  };
}
```

framework の `nixosPolicyMaterializerModule` が system スコープと user スコープの両方から enabled feature の policy を集約し、`local.nixpkgsPolicy.{unfree, permittedInsecure}` へ `lib.mkAfter` で投影します。さらに `nixpkgsPolicyModule` がそれを `nixpkgs.config.allowUnfreePredicate` / `nixpkgs.config.permittedInsecurePackages` へ流します。

embedded Home Manager は `useGlobalPkgs = true` なので、NixOS 側 `pkgs` の policy がそのまま効きます。standalone Home Manager 構成では `homePolicyMaterializerModule` が `local.nixpkgsPolicy` を別途 materialize します。

## ホスト例

`modules/00-hosts/neko5/configuration.nix`:

```nix
{inputs, ...}: {
  configurations.nixos.neko5.module = {
    local.features = {
      neko5-hardware.enable = true;
      nix.enable = true;
      zsh.enable = true;
      # ...
    };

    local.users.tenzyu = {
      enable = true;
      isAdmin = true;
      homeStateVersion = "26.05";
      email = "tenzyu.on@gmail.com";
      homeDirectory = "/home/tenzyu";

      features = {
        steam.enable = true;
        parsec.enable = true;
        catppuccin.enable = true;
        # ...
      };
    };
  };
}
```

system feature は host の capabilities (driver, daemon など) を表し、user feature は各ユーザーが自宅環境として欲しいものを表します。

## ホスト一覧

| Host | 概要 |
| --- | --- |
| `neko5` | Hyprland desktop / laptop。GUI、音声、Bluetooth、fcitx5、各種 desktop app。 |
| `neko6` | NixOS-WSL。CLI 中心の Home Manager 構成 + WSL 向け system 設定。 |
| `neko7` | qemu guest / Docker / server 寄り。NVIDIA ドライバ、最小限の Home Manager。 |

## よく使う操作

```sh
nix fmt
nix flake check
nix build .#nixosConfigurations.neko5.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#neko5
nix flake update
```

## 機能追加の流れ

### 1. Pure NixOS 機能

`modules/50-features/<feature>.nix`:

```nix
{
  flake.modules.nixos.<feature> = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.<feature>.enable {
      services.<feature>.enable = true;
    };
  };
}
```

`modules/00-hosts/<host>/configuration.nix`:

```nix
local.features.<feature>.enable = true;
```

### 2. Pure Home Manager 機能

`modules/50-features/<feature>.nix`:

```nix
{
  flake.modules.homeManager.<feature> = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.<feature>.enable {
      home.packages = [pkgs.<feature>];
    };
  };
}
```

ユーザー側で有効化する場合:

```nix
local.users.tenzyu.features.<feature>.enable = true;
```

### 3. 両方の境界をまたぐ機能

NixOS 側と Home Manager 側の両方を 1 ファイルに書きます。feature は user agnostic に書きます。

```nix
{
  flake.modules.nixos.<feature> = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.<feature>.enable {
      environment.systemPackages = [pkgs.<feature>];
    };
  };

  flake.modules.homeManager.<feature> = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.<feature>.enable {
      home.packages = [pkgs.<feature>];
    };
  };
}
```

### 4. user 限定 feature (per-user にグループ追加など)

`helpers.mapUsersWithFeature` を使って `users.users` 形の attrset を返し、NixOS の `users.users` に merge します。`mapUsersWithFeature` は enabled ユーザーだけを抽出し、各ユーザーに対して `f name user` の返り値を `users.users.<name>` 配下に置きます。

```nix
{
  flake.modules.nixos.<feature> = {
    config,
    helpers,
    lib,
    ...
  }: {
    config.users.users =
      helpers.mapUsersWithFeature "<feature>" config
      (name: _user: {
        extraGroups = lib.mkAfter ["<group>"];
      });
  };
}
```

`lib.mkAfter` を使って他の module からの追記を許可します。framework の `nixosUserAccountsModule` が `isNormalUser` / `group` / `home` / `extraGroups` の base 値を materialize するので、feature 側は追加分だけ書けば足ります。

### 5. unfree / insecure package を使う feature

`flake.local.featurePolicies.<feature>.{unfree, permittedInsecure}` に package 名を列挙します。framework の materializer が `nixpkgs.config` まで投影します。

```nix
{
  flake.local.featurePolicies.<feature>.unfree = ["<package>"];

  flake.modules.nixos.<feature> = {...}: {
    config = lib.mkIf config.local.features.<feature>.enable {};
  };

  flake.modules.homeManager.<feature> = {...}: {
    config = lib.mkIf config.local.features.<feature>.enable {
      home.packages = [pkgs.<package>];
    };
  };
}
```

`flake.local.featurePolicies` は flake-level の純粋宣言で、`nixpkgs.config` には影響しません。`nixosPolicyMaterializerModule` が enabled feature を見て `local.nixpkgsPolicy` にコピーし、そこから `nixpkgs.config` へ反映されます。

### 6. bundle feature

`flake.modules.nixos.<bundle>` / `flake.modules.homeManager.<bundle>` は空で、`config.local.features.<other>.enable = true;` だけを書きます。Home Manager 側にも対になるマーカーモジュールを置く必要があります (現在 `local.users.<name>.features` の attrset は home feature 名から生成されているため、bundle 名も対を成す必要あり)。

```nix
{
  flake.modules.nixos.<bundle> = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.<bundle>.enable {
      local.features.<other-a>.enable = true;
      local.features.<other-b>.enable = true;
    };
  };

  flake.modules.homeManager.<bundle> = {config, lib, ...}: {
    config = lib.mkIf config.local.features.<bundle>.enable {};
  };
}
```

## 非目標

この nixfiles は、汎用フレームワークや他人向けテンプレートを目指していません。

優先しているのは次の性質です。

- 自分のホスト構成を素早く読めること
- 新しい機能を小さなファイルとして足せること
- 例外的な package policy を feature 単位で追跡できること
- 抽象化は、実際の重複や環境差分を減らす場合にだけ導入すること

## Gaming runtime

This repo keeps gaming optimizations explicit instead of hiding them behind global state.

`gaming-core` を有効化すると、以下のコマンドが user の `home.packages` から使えるようになります。

| コマンド | 役割 |
| --- | --- |
| `game-scope %command%` | `gamemoderun` + `gamescope` をまとめて起動する汎用ラッパー。Steam の per-game launch options に指定する。 |

`hyprland-gaming-mode` を有効化すると、以下のコマンドが追加されます。

| コマンド | 役割 |
| --- | --- |
| `hypr-gaming-mode on\|off` | Hyprland の animation / blur / shadow / gap / vrr などを一括でゲーム向けプロファイルに切り替える。GameMode 起動時の `start` / `end` hook もこの feature が担う。 |

`osu-lazer` を有効化すると `osu-lazer` / `osu-lazer-raw` の2つのラッパーが `home.packages` から使えるようになります。

- `osu-lazer` は `gamemoderun` 経由で `osu-lazer-bin` を起動する。`hyprland-gaming-mode` が有効なら on/off を連動させる。
- `osu-lazer-raw` は `gamemoderun` も `gamescope` も挟まない素の起動。

Steam per-game launch options の典型:

```bash
game-scope %command%
```

必要なら `game-scope` 内の env で geometry を上書きする。

```bash
GAMESCOPE_OUTPUT_WIDTH=1366 \
GAMESCOPE_OUTPUT_HEIGHT=768 \
GAMESCOPE_GAME_WIDTH=1024 \
GAMESCOPE_GAME_HEIGHT=576 \
GAMESCOPE_REFRESH=60 \
GAMESCOPE_SCALER=fsr \
game-scope %command%
```

`osu-lazer` は `gamemoderun` 単体で `osu-lazer-bin` を起動するラッパーであり、
`GAMESCOPE_*` 環境変数は読みません。osu 側でフルスクリーン設定を使ってください。

`osu-lazer-raw` はラッパーを完全に外した素の起動で、起動が遅い／GPU スタッキングを疑うときの切り札です。

MangoHud is intentionally not installed by default. It is useful for diagnostics and frame-time logging, but it is not part of the runtime path needed to make GameMode or gamescope work.
