# tenzyu's nixfiles

個人用のNixOS / home-manager構成です。

このリポジトリは、flake本体を薄く保ち、実体を`modules/`配下の小さな機能モジュールとして登録し、各ホストで必要なものを明示的に選んで合成する方針で作られています。

設計の中心にあるのは **「明示的合成を重視した、Dendritic風の個人環境モジュールカタログ」** です。

## 設計思想

このnixfilesの基本方針は次の通りです。

- **flakeは入口に徹する**  
  `flake.nix`はinputsと`mkFlake`、`import-tree ./modules`だけに近い形に保ちます。構成ロジックは`modules/`へ寄せます。

- **機能を小さく登録し、ホストで選ぶ**  
  SSH、zsh、Docker、Hyprland、Neovimなどを`flake.modules.<class>.<feature>`として登録し、ホスト定義ではimportsに並べます。

- **ホストは完成品ではなく部品表として読む**  
  `modules/00-hosts/<host>/configuration.nix`を見ると、そのホストに何が入っているかがリストとして分かるようにします。

- **NixOSとhome-managerの境界を薄い合成層で吸収する**  
  NixOS統合home-managerとstandalone home-managerの差分は`factory`層と`cross`層で扱います。

- **例外は局所化する**  
  `unstable`、unfree、insecure packageの許可はグローバルに広げず、必要な機能の近くで宣言します。

- **抽象化しすぎない**  
  roleやprofileを深く積むのではなく、ホストごとのimportsを明示します。重複削減よりも、読んで分かる構成を優先します。

## アーキテクチャ

```text
flake.nix
  inputs + flake-parts + import-tree

modules/
  flake/
    flake-parts.nix             flake.modulesを有効化し、nixos/homeManager/cross引数を配る
    factory-nixos.nix           configurations.nixos -> flake.nixosConfigurations
    factory-home-manager.nix    configurations.homeManager -> flake.homeConfigurations
    formatter.nix               perSystem formatter
    systems.nix                 supported systems

  identity/
    me.nix                      username, email, timezone, stateVersionなどの個人情報

  pkgs/
    runtime.nix                 unstable / unfree / insecure package policy

  nixos/
    *.nix                       NixOS機能モジュール

  home/
    *.nix                       home-manager機能モジュール

  cross/
    00-registry.nix             NixOS + home-manager境界をまたぐ機能DSL
    *.nix                       standaloneでもNixOS統合でも使いたい機能

  00-hosts/
    neko5/
    neko6/
    neko7/                      ホストごとの合成点
```

## flake本体

`flake.nix`は依存関係のマニフェストです。

outputsは次の形に集約されています。

```nix
outputs = inputs:
  inputs.flake-parts.lib.mkFlake {inherit inputs;}
  (inputs.import-tree ./modules);
```

`import-tree`により、`modules/`配下のNixファイルは自動でflake-parts moduleとして読み込まれます。そのため、新しい機能を追加するときに`flake.nix`のimport listを編集する必要はありません。

## module登録

各機能は`flake.modules`へ登録します。

NixOS機能は次のような形です。

```nix
{
  flake.modules.nixos.ssh = {
    services.openssh.enable = true;
  };
}
```

home-manager機能は次のような形です。

```nix
{
  flake.modules.homeManager.zsh = {
    programs.zsh.enable = true;
  };
}
```

ホスト側では、登録済みの機能をimportsに並べます。

```nix
{
  nixos,
  homeManager,
  ...
}: {
  configurations.nixos.example.module = {
    imports = [
      nixos.nix
      nixos.ssh
      nixos.homeManagerUser
      {
        home-manager.users.tenzyu.imports = [
          homeManager.common
          homeManager.zsh
          homeManager.neovim
        ];
      }
    ];
  };
}
```

このrepoでは「どのホストが何を使うか」を隠さず、ホスト定義に明示する方針です。

## factory層

`modules/flake/factory-nixos.nix`は、repo内DSLである`configurations.nixos`を`flake.nixosConfigurations`へ変換します。

`modules/flake/factory-home-manager.nix`は、`configurations.homeManager`を`flake.homeConfigurations`へ変換します。

これにより、各ホストやstandalone home-manager構成は、flake outputsを直接組み立てるのではなく、統一された内部インターフェースに宣言できます。

## cross層

`modules/cross/`は、このrepoの独自性が最も強い層です。

目的は、次の2つの環境で同じ機能定義を使えるようにすることです。

- NixOS上の`home-manager.users.<user>`
- standalone home-manager

たとえばGUIアプリやテーマのように、NixOS側の設定とhome-manager側の設定がセットになる機能があります。`cross`ではそれを1つの定義として書けます。

```nix
{
  local.cross.definitions.example = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
    ];

    nixos.module = {
      # NixOS側にだけ必要な設定
    };

    home.module = {
      # home-manager側に必要な設定
    };
  };
}
```

ホスト側では`cross.user`でNixOS側importsとhome-manager側importsをまとめて注入します。

```nix
(cross.user "tenzyu" (
  (with cross.modules; [
    discord
    obsidian
    hyprland
  ])
  ++ (with homeManager; [
    common
    zsh
    neovim
  ])
))
```

`cross`は「環境差分を機能側で吸収し、ホスト側では選択だけに集中する」ための仕組みです。

## package policy

`modules/pkgs/runtime.nix`は、package policyを共通化します。

主なオプションは次の通りです。

- `local.pkgs.useUnstable`
- `policy.pkgs.allowUnfreeNames`
- `policy.pkgs.allowUnfreePredicates`
- `policy.pkgs.permittedInsecurePackages`

たとえば`prismlauncher`は、その機能定義の中で`unstable`とunfree許可を宣言します。

```nix
{
  local.cross.definitions.prismlauncher = {
    ambient = [
      {local.pkgs.useUnstable = true;}
      {policy.pkgs.allowUnfreeNames = ["prismlauncher"];}
    ];

    home.packages = pkgs: [
      pkgs.unstable.prismlauncher
    ];
  };
}
```

この方針により、例外的なpackage policyが「なぜ必要か」を機能の近くで追えます。

## ホスト

現在のNixOSホストは次の通りです。

| Host | 概要 |
| --- | --- |
| `neko5` | Hyprland desktop / laptop寄りのメイン環境。GUI、音声、Bluetooth、fcitx5、LLM agent、各種desktop appを含む。 |
| `neko6` | WSL向け環境。NixOS-WSL、Docker、開発用CLI中心のhome-manager構成を含む。 |
| `neko7` | qemu guest / Docker / server寄り設定を含むNixOS環境。network周りの調整と最小限のhome-manager構成を持つ。 |

ホストを読むときは、まず`modules/00-hosts/<host>/configuration.nix`を見ます。そこに並んでいるimportsが、そのホストの構成要素です。

## よく使う操作

format:

```sh
nix fmt
```

flake全体の検査:

```sh
nix flake check
```

NixOS構成のbuild:

```sh
nix build .#nixosConfigurations.neko5.config.system.build.toplevel
```

NixOSへ適用:

```sh
sudo nixos-rebuild switch --flake .#neko5
```

input更新:

```sh
nix flake update
```

## 機能追加の流れ

### NixOS機能を追加する

1. `modules/nixos/<feature>.nix`を作る
2. `flake.modules.nixos.<feature>`を定義する
3. 使いたいホストのimportsに`nixos.<feature>`を追加する

例:

```nix
{
  flake.modules.nixos.exampleService = {
    services.example.enable = true;
  };
}
```

### home-manager機能を追加する

1. `modules/home/<feature>.nix`を作る
2. `flake.modules.homeManager.<feature>`を定義する
3. 使いたいホストのhome-manager importsに`homeManager.<feature>`を追加する

例:

```nix
{
  flake.modules.homeManager.exampleTool = {
    programs.example.enable = true;
  };
}
```

### cross機能を追加する

NixOS統合home-managerとstandalone home-managerの両方で使いたい機能は`modules/cross/<feature>.nix`に置きます。

1. `local.cross.definitions.<feature>`を定義する
2. 必要なら`ambient`にpackage policyを書く
3. 必要なら`nixos.module`と`home.module`を分ける
4. ホスト側で`cross.modules.<feature>`を選ぶ

例:

```nix
{
  local.cross.definitions.exampleApp = {
    ambient = [
      {local.pkgs.useUnstable = true;}
    ];

    home.packages = pkgs: [
      pkgs.unstable.example-app
    ];
  };
}
```

## 命名と配置の方針

- NixOSだけに関係するものは`modules/nixos/`
- home-managerだけに関係するものは`modules/home/`
- 両方の境界をまたぐものは`modules/cross/`
- flake output生成や共通配線は`modules/flake/`
- ユーザー情報は`modules/identity/`
- package policyやpkgs runtimeは`modules/pkgs/`
- ホスト合成は`modules/00-hosts/`

このrepoでは、ディレクトリは純粋なDendritic Patternよりもクラス別に分かれています。意図は、Dendriticの「機能カタログとして登録して合成する」利点を取り入れつつ、個人用repoとして読みやすいnamespaceを残すことです。

## 非目標

このnixfilesは、汎用フレームワークや他人向けテンプレートを目指していません。

優先しているのは次の性質です。

- 自分のホスト構成を素早く読めること
- 新しい機能を小さなファイルとして足せること
- 例外的なpackage policyを追跡できること
- NixOSとhome-managerの重複を減らしすぎず、必要な場所で明示できること

抽象化は、実際の重複や環境差分を減らす場合にだけ導入します。

## まとめ

このrepoは、次の一文で表せます。

> ホストは薄く、機能は小さく、例外は局所化し、NixOSとhome-managerの境界は合成層で吸収する。

そのため、読む順番は次がおすすめです。

1. `flake.nix`
2. `modules/flake/flake-parts.nix`
3. `modules/flake/factory-*.nix`
4. `modules/cross/00-registry.nix`
5. `modules/00-hosts/<host>/configuration.nix`
6. そこから参照されている`modules/nixos/`、`modules/home/`、`modules/cross/`の各機能

## Gaming runtime

This repo keeps gaming optimizations explicit instead of hiding them behind global state.

Available commands:

```bash
# Generic wrapper. Use this in Steam per-game launch options.
game-run %command%

# Fallback when a game breaks under gamescope but should still request GameMode.
game-run-noscope %command%

# Steam inside GameMode + gamescope from the normal Hyprland session.
steam-gaming

# osu! lazer default launcher, wrapped with GameMode + gamescope.
osu-lazer

# Escape hatch for debugging osu! lazer without the wrapper.
osu-lazer-raw
```

Default gamescope geometry is tuned for the current 1366x768 laptop panel. Override per launch when needed:

```bash
GAMESCOPE_WIDTH=1280 GAMESCOPE_HEIGHT=720 GAMESCOPE_REFRESH=60 osu-lazer
```

MangoHud is intentionally not installed by default. It is useful for diagnostics and frame-time logging, but it is not part of the runtime path needed to make GameMode or gamescope work.
