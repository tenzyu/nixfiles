# tenzyu's nixfiles

個人用のNixOS / home-manager構成です。

このリポジトリは、flake本体を薄く保ち、実体を`modules/`配下の小さな機能モジュールとして登録し、各ホストで必要なものを明示的に選んで合成する方針で作られています。

設計の中心にあるのは **Dendritic Pattern** に近いaspect指向のモジュール配置です。NixOS / home-manager / クロスユーザーprojectionを1ファイル単位の `feature` として登録し、ホストは `feature.system` / `feature.users` へ feature 名を並べるだけで両側を束縛します。

## 設計思想

このnixfilesの基本方針は次の通りです。

- **flakeは入口に徹する**  
  `flake.nix`はinputsと`mkFlake`、`import-tree ./modules`に近い形だけを保ちます。構成ロジックは`modules/`へ寄せます。

- **機能を小さく登録し、ホストで選ぶ**  
  SSH、zsh、Docker、Hyprland、Neovimなどは `flake.modules.<class>.<feature>` として登録します。ホスト定義では `feature.system` / `feature.users` へ feature 名を並べるだけにします。

- **ホストは完成品ではなく部品表として読む**  
  `modules/00-hosts/<host>/configuration.nix`を見ると、そのホストに何が入っているかがリストとして分かるようにします。

- **NixOSとhome-managerの境界を薄い合成層で吸収する**  
  同じ `feature.key` に対して `flake.modules.nixos.<feature>` と `flake.modules.homeManager.<feature>` を登録し、ホストは projector へ feature 名を列挙するだけで両側を束縛します。

- **例外は局所化する**  
  `unstable`、unfree、insecure packageの許可はグローバルに広げず、必要な feature の `flake.effects.<name>.system.collect` / `flake.effects.<name>.user.collect` で局所的に宣言します。

- **抽象化しすぎない**  
  roleやprofileを深く積むのではなく、ホストごとの `features.<name> = true;` 列挙を明示します。同一 projector 内の dedupe は materializer が保証します。

## アーキテクチャ

```text
flake.nix
  inputs + flake-parts + import-tree

modules/
  flake/
    flake-parts.nix          flake.modules / flake.effects を有効化し、
                             nixos / homeManager / feature 引数を配る
    factory-nixos.nix        configurations.nixos -> flake.nixosConfigurations
                             + collector module (`flake.modules.nixos.collector`)
                             を host module へ自動注入
    factory-home-manager.nix configurations.homeManager -> flake.homeConfigurations
                             (low priority; standalone Home Manager 用のfactory)
    factory-user.nix         per-user な NixOS user module と Home Manager user module
                             を生成する `flake.lib.userFactory` (User Factory Aspect)
                             を提供。`feature.users` が内部で呼び出す。
    feature.nix              flake.lib.feature.{system, users} を提供する
                             materializer
    collector.nix            `local.effects` の schema
                             + `flake.modules.nixos.collector` module
                             (cross-cutting policy を nixpkgs.config へ投影)
    formatter.nix            perSystem formatter
    systems.nix              supported systems

  pkgs/
    runtime.nix              pkgs.unstable / pkgs.llm-agents.* などの
                             常駐 overlay (flake.modules.nixos.pkgs-runtime)

  nixos/
    *.nix                    NixOS機能モジュール

  home/
    *.nix                    home-manager機能モジュール

  features/
    *.nix                    NixOS + home-managerの境界をまたぐ機能
                             および effect-only の bundle

  00-hosts/
    neko5/                   Hyprland desktop / laptop
    neko6/                   NixOS-WSL
    neko7/                   server / proxmox-guest
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

## 命名規約

**すべての feature 名と host-facing ファイル名は kebab-case** に統一します。

- 例: `tenzyu-cli` / `tenzyu-desktop` / `docker-rootless` / `networkmanager-access` / `systemd-boot` / `hyprland-core` / `hyprland-tenzyu` / `nvidia-graphics` / `proxmox-guest`
- 内部 let binding や private な helper 関数名はこの限りではありません。
- `flake.modules.nixos.pkgs-runtime` のような factory plumbing も kebab-case に統一しています。
- ホスト hardware は `flake.modules.nixos.neko5-hardware` / `neko7-hardware` として kebab-case 化しています。

## module登録

各機能は `flake.modules.<class>.<feature>` へ登録します。

NixOS機能は次のような形です。

```nix
# modules/nixos/example-service.nix
{
  flake.modules.nixos.example-service = {
    services.example.enable = true;
  };
}
```

home-manager機能は次のような形です。

```nix
# modules/home/example-tool.nix
{
  flake.modules.homeManager.example-tool = {
    programs.example.enable = true;
  };
}
```

両方の境界をまたぐ機能は `modules/features/` に置き、`flake.modules.nixos.<feature>` と `flake.modules.homeManager.<feature>` の両方を定義します。

```nix
# modules/features/example-app.nix
{
  flake.modules.nixos.example-app = {};

  flake.modules.homeManager.example-app = {pkgs, ...}: {
    home.packages = [pkgs.example-app];
  };
}
```

`flake.modules.nixos.<feature>` と `flake.modules.homeManager.<feature>` は **payload** であり、低レベル API です。ホストは原則として `feature.system` / `feature.users` 経由で feature 名を列挙し、materializer に解決を任せます。`flake.modules` を直接 `imports` に書くことは **通常行いません**。

## factory層

`modules/flake/factory-nixos.nix` は、リポジトリ内DSLである `configurations.nixos` を `flake.nixosConfigurations` へ変換します。`modules/flake/factory-home-manager.nix` は `configurations.homeManager` を `flake.homeConfigurations` へ変換します。

`factory-nixos.nix` のもうひとつの責務は **collector module** の注入です。collector は `modules/flake/collector.nix` で `flake.modules.nixos.collector` として登録されており、factory が `flake.nixosConfigurations.<host>.modules` へ自動的に組み込みます。collector は `local.effects` option を定義し、その値を `nixpkgs.config.allowUnfreePredicate` や `nixpkgs.config.permittedInsecurePackages` などの cross-cutting な policy 設定へ投影します。

`factory-home-manager.nix` は **low priority** の standalone Home Manager 用の factory です。`flake.modules.nixos.pkgs-runtime` は NixOS 専用の module なので、standalone Home Manager 側では `withSystem` 経由で取り出した `inputs'.nixpkgs.legacyPackages` に直接 overlay を `appendOverlays` で適用します。同一 feature キーで standalone と NixOS統合のどちらでも評価できる設計ではありません。

## feature層

`flake.lib.feature` は、NixOS統合home-manager 上で **同じ feature key** から `flake.modules.nixos.<feature>` と `flake.modules.homeManager.<feature>` の双方を引き、`flake.effects.<feature>` の projection contract を実行する薄い materializer です。feature モジュールはユーザ束縛を知りません。ホストだけが「どのマシンが、どのユーザに、どの feature を」を決めます。

### 2つの projector

| 名前 | 役割 |
| --- | --- |
| `feature.system` | NixOS system materializer。`features` の closure を解決し、`flake.modules.nixos.<feature>` を host の imports に、`flake.effects.<feature>.system` の `config` を host NixOS module へ、`collect` を `local.effects` へ投影する。`flake.modules.homeManager.<feature>` は触らない。 |
| `feature.users` | 複数ユーザー対応 materializer。`flake.effects.<feature>.user` の `config` を user ごとに NixOS module へ投影し、`users.users.<username>` / `home-manager.users.<username>` を組み立てる。`system` 側 (`flake.modules.nixos.<feature>` + `effects.<feature>.system`) は host 全体で 1 回だけ `feature.users` 内部で import / project される。複数ユーザーが同じ feature を要求しても NixOS 側は重複しない。 |

### materializer が共通でやること

- `features` の enabled 名前を `lib.unique` + `lib.naturalSort` で正規化する
- `flake.effects.<name>.requires` の transitive closure を解決する
- closure の各 feature 名について `flake.modules.nixos.<name>` / `flake.modules.homeManager.<name>` を解決する
- closure の各 feature 名について `flake.effects.<name>.system` / `flake.effects.<name>.user` を評価する
- 投影結果の `config` は **NixOS module system の `imports` に積まれる**ため、module system の merge semantics に従う
- 投影結果の `collect` は `local.effects.*` へ (NixOS module system の submodule merge で) 結合される
- 同一 projector 呼び出し内で重複する feature 名・重複する import は **dedupe される**
- 未知の feature 名は `feature.<projector>.<context>: unknown feature '<name>'` で評価時に throw する
- enabled features が空 (`features = {};` を含むすべて-false を含む) なら `feature.<projector>.<context>: no enabled features` で throw する
- `feature.users {}` のような空 users マップも `feature.users: users is empty` で throw する
- 結果として、`flake.modules` の class surface は payload 専用、policy は `local.effects` 専用、依存関係は `flake.effects` 専用、と3層に綺麗に分かれる

### どの projector を選ぶか

- 「マシンが備えるか」で有効化する feature は `feature.system` (`neko5-hardware` / `nvidia-graphics` / `docker-rootless` / `systemd-boot` など)
- 「誰が使うか」で有効化する feature は `feature.users` (`tenzyu-desktop` / `hyprland-tenzyu` / `catppuccin` / `steam` / `prismlauncher` / `codex` など)
- 複数ユーザーで共有する user capability は同じ `feature.users` を1回の呼び出しで複数ユーザー分束ねる

### Dedupe に関する正直な仕様

- **同一 projector 内の dedupe は保証される**  
  `feature.system` 呼び出しの中で重複する feature 名は1度しか評価されない。`feature.users` 呼び出しの中で複数ユーザーが同じ feature を要求しても、`flake.modules.nixos.<feature>` は host imports に1回だけ積まれ、`system effect` の `collect` も1回だけ `local.effects` に merge される。

- **異なる projector 呼び出し間の dedupe は保証されない**  
  `feature.system` と `feature.users` は独立した projector 呼び出しである。host 側で `feature.system` に書いた feature 名と `feature.users` の closure が overlap する場合、両 projector がそれぞれ projection を行う。これは **host 側の規約** で回避する (例: `networkmanager-access.requires = ["networkmanager"]` なら `feature.system` 側に `networkmanager` を併記しない)。

- **真の全体 dedupe を導入する `feature.host` は導入しない**  
  これは公開モデルを厚くするので採用しない。host 規約で overlap を避ければ十分である。

### Merge semantics

effect の `config` は **NixOS module の `imports` に1つずつ積まれる**ため、module system の merge 規則に従います:

- `listOf` 系の attribute (`users.users.<name>.extraGroups` など) は plain list で書くと **concat** される。`mkOverride` 系 (`mkDefault` / `mkForce` / `mkAfter` / `mkBefore`) を使うと priority で決着する。effect 側は plain list を推奨。
- `submodule` 系の attribute は attrset 単位で deep merge される。
- 同じ attribute に同じ priority で複数設定が衝突する場合 (`extraGroups = ["wheel"];` を materializer と WSL module の両方が書くケースなど) は module system が concat するため **重複した値がそのまま残る**。これは既知の cosmetic issue であり、`lib.unique` での dedupe は module system 側では行われない。必要なら呼び出し側で `lib.mkForce` 等を使う。

## ホスト例

`modules/00-hosts/neko5/configuration.nix` の最終形:

```nix
{ feature, inputs, ... }: {
  configurations.nixos.neko5.module = {
    imports = [
      (feature.system {
        stateVersion = "26.05";
        features = {
          neko5-hardware = true;
          nix = true;
          nix-store-clean = true;
          zsh = true;
          time = true;
          locale = true;
          ssh = true;
          tailscale = true;
          systemd-boot = true;
          pipewire = true;
          bluetooth = true;
          intel-graphics = true;
          docker-rootless = true;
          fcitx5 = true;
          kernel-latest = true;
          udiskie = true;
          hyprlock = true;
          open-tablet-driver = true;
          stub-ld = true;
          laptop-input = true;
          fonts = true;
          desktop-performance = true;
          wayland-session = true;
        };
      })

      (feature.users {
        tenzyu = {
          isAdmin = true;
          homeStateVersion = "26.05";
          fullName = "tenzyu";
          email = "tenzyu.on@gmail.com";

          features = {
            tenzyu-desktop = true;
            hyprland-tenzyu = true;
            hyprland-gaming-mode = true;
            steam = true;
            android-mic = true;
            discord = true;
            prismlauncher = true;
            codex = true;
            opencode = true;
            obsidian = true;
            osu-lazer = true;
            parsec = true;
            networkmanager-access = true;
            nix-access = true;
            rtk = true;
            catppuccin = true;
            dolphin = true;
          };

          imports = [
            ({ pkgs, ... }: {
              home.packages = with pkgs; [
                nh jq jqp lazygit zip ncdu crosspipe gh qdirstat
                inputs.castalia.packages.${pkgs.system}.castalia
                inputs.onair.packages.${pkgs.system}.default
              ];
            })
          ];
        };
      })
    ];
  };
}
```

`feature.system` の `features` に `<feature> = true;` を書くと、materializer が `flake.effects.<feature>.requires` を辿り transitive closure を取り込み、それから projection を行う。`networkmanager-access` のように user feature が system 側 feature を `requires` する場合、`feature.system` 側にその system 側 feature を併記する必要はない。

`feature.users` にはユーザー spec を **そのまま inline で渡す**。`feature.users` の引数が source of truth であり、materializer は内部の `userFactory` (User Factory Aspect) を呼び出してユーザーごとの NixOS user module と Home Manager user module を生成する。

## package policy

`modules/pkgs/runtime.nix` は、共通の overlay (`pkgs.unstable` / `pkgs.llm-agents.*`) を提供します。policy 決定は持たず、host 側の imports に自動的に組み込まれます。

### 例外は feature の近くで宣言する

`unfree` / `insecure` な package の許可はグローバルに広げず、必要な feature の `flake.effects.<name>.collect` で局所的に宣言します。

- `flake.effects.<name>.system.collect.pkgs.unfreePackages`
- `flake.effects.<name>.user.collect.pkgs.unfreePackages`
- `flake.effects.<name>.system.collect.pkgs.permittedInsecurePackages`
- `flake.effects.<name>.user.collect.pkgs.permittedInsecurePackages`

materializer は各 effect の `collect` を `local.effects.*` へ module として投影し、collector module (`flake.modules.nixos.collector`) が最終的に `lib.unique` で重複を除いた値を `nixpkgs.config.allowUnfreePredicate` / `nixpkgs.config.permittedInsecurePackages` へ投影します。

たとえば `prismlauncher` は unfree 許可だけを宣言します。

```nix
{
  flake.effects.prismlauncher = {
    system = {
      collect.pkgs.unfreePackages = ["prismlauncher"];
    };
  };

  flake.modules.nixos.prismlauncher = {};

  flake.modules.homeManager.prismlauncher = {pkgs, ...}: {
    home.packages = [
      (pkgs.unstable.prismlauncher.override {jdks = [pkgs.unstable.jdk21];})
    ];
  };
}
```

cross-feature な依存関係は `flake.effects.<name>.requires = [...]` で宣言します。

```nix
# modules/features/steam.nix
{
  flake.effects.steam = {
    requires = ["gaming-core"];

    system = {
      collect.pkgs.unfreePackages = [
        "steam"
        "steam-original"
        "steam-unwrapped"
        "steam-run"
      ];
    };
  };

  flake.modules.nixos.steam = {pkgs, ...}: {programs.steam.enable = true;};
  flake.modules.homeManager.steam = {pkgs, ...}: {home.packages = [];};
}
```

materializer は `steam` の `requires` を辿り `gaming-core` も closure に取り込んでから projection するため、host 側で `features.gaming-core = true;` を併記する必要はありません。

### schema は `local.effects.*` だけで拡張する

将来の policy 軸 (substituters / trusted-public-keys / fonts / xdg-portals / security exceptions / ...) は **すべて** `local.effects` の schema 拡張として扱います。`flake.modules.<class>.*` の class surface は payload 専用、`flake.effects.<name>.user` / `.system` の `config` は NixOS module 属性専用、と層を固定することで、policy の種類が増えても projector / factory を書き換えずに済みます。

## ホスト

現在のNixOSホストは次の通りです。

| Host | 概要 |
| --- | --- |
| `neko5` | Hyprland desktop / laptop寄りのメイン環境。GUI、音声、Bluetooth、fcitx5、LLM agent、各種desktop appを含む。 |
| `neko6` | NixOS-WSL。開発用CLI中心のhome-manager構成とWSL向けsystem設定。`wsl-default-user` user effect によりデフォルトユーザを設定。 |
| `neko7` | qemu guest / Docker / server寄り設定。`proxmox-guest` (= `qemu-guest-profile` + `qemu-guest-agent`)、NVIDIA ドライバ、最小限の home-manager 構成。 |

ホストを読むときは、まず`modules/00-hosts/<host>/configuration.nix`を見ます。そこに並んでいる`imports`と、`feature.system` / `feature.users` に列挙された feature 名が、そのホストの構成要素です。

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

feature には次の典型形があります。1つの feature は **同じ kebab-case 名** で `flake.modules.<class>.<name>` / `flake.effects.<name>` に登録され、ホストは projector の `features.<name> = true;` に名前を並べるだけで両側を束縛します。

### 1. Pure NixOS 機能を追加する

1. `modules/nixos/<feature>.nix` を作り、`flake.modules.nixos.<feature>` を定義する
2. host の `feature.system` 呼び出しの `features` に `<feature> = true;` を加える

```nix
# modules/nixos/example-service.nix
{
  flake.modules.nixos.example-service = {
    services.example.enable = true;
  };
}
```

```nix
# host
imports = [
  (feature.system {
    features.example-service = true;
  })
];
```

### 2. Pure home-manager 機能を追加する

1. `modules/home/<feature>.nix` を作り、`flake.modules.homeManager.<feature>` を定義する
2. host の `feature.users <users>` の `users.<name>.features` に `<feature> = true;` を加える

```nix
# modules/home/example-tool.nix
{
  flake.modules.homeManager.example-tool = {
    programs.example.enable = true;
  };
}
```

```nix
# host
imports = [
  (feature.users {
    tenzyu = {
      features.example-tool = true;
    };
  })
];
```

### 3. 両方の境界をまたぐ機能を追加する

NixOS統合home-manager で使いたい機能は `modules/features/<feature>.nix` にまとめ、`flake.modules.nixos.<feature>` と `flake.modules.homeManager.<feature>` の両方を定義します。feature は user agnostic に書き、user 固有の情報は `flake.effects.<feature>.user` 内の `user` レコード (`name` / `fullName` / `email` / `isAdmin` / `shell` / `homeStateVersion` / `homeDirectory`) で識別します。

```nix
# modules/features/example-app.nix
{
  flake.modules.nixos.example-app = {};

  flake.modules.homeManager.example-app = {pkgs, ...}: {
    home.packages = [pkgs.example-app];
  };
}
```

### 4. cross-cutting policy (unfree / insecure) を必要とする場合

`flake.effects.<feature>.system` または `.user` の `collect` を使います。`collect` は materializer によって `local.effects.*` へ (module system merge で) 投影され、collector module が `nixpkgs.config.*` へ投影します。

```nix
{
  flake.modules.nixos.example-service = {
    services.example.enable = true;
  };

  flake.effects.example-service = {
    system = {
      collect.pkgs.unfreePackages = ["example-service"];
    };
  };
}
```

### 5. per-user projection (extra groups, trusted users, ...) を必要とする場合

`flake.effects.<feature>.user` の `config` を使います。`{user, ...}` を受け取り、`config` 内に host NixOS attribute (`users.users.${user.name}.extraGroups` や `nix.settings.extra-trusted-users` や `wsl.defaultUser` など) を書けます。

**重要**: `effects.<name>.user.config` は **user-contextual な NixOS module fragment** であり、Home Manager module には merge されません。Home Manager 用の payload は `flake.modules.homeManager.<name>` 側に書きます。

```nix
{
  flake.effects.docker-user-access = {
    user = {user, ...}: {
      config = {
        users.users.${user.name}.extraGroups = ["docker"];
      };
    };
  };
}
```

```nix
{
  flake.effects.wsl-default-user = {
    requires = ["wsl-integration"];

    user = {user, ...}: {
      config = {
        wsl.defaultUser = user.name;
      };
    };
  };
}
```

### 6. 他の feature に依存する場合

`flake.effects.<feature>.requires = [...]` に依存 feature 名を並べます。materializer が transitive closure を解決してから projection するため、host 側で `requires` 先の feature を `features` に併記する必要はありません。

```nix
{
  flake.effects.steam = {
    requires = ["gaming-core"];

    system = {
      collect.pkgs.unfreePackages = ["steam"];
    };
  };

  flake.modules.nixos.steam = {pkgs, ...}: {programs.steam.enable = true;};
  flake.modules.homeManager.steam = {pkgs, ...}: {home.packages = [];};
}
```

### 7. 同じ意味の feature を束ねたい (bundle)

profile 抽象は導入しません。代わりに `flake.effects.<name>.requires` を長くした bundle effect を使います。`tenzyu-cli` / `tenzyu-desktop` / `proxmox-guest` / `hyprland-tenzyu` などがこのパターンです。

```nix
# modules/features/tenzyu-cli.nix
{
  flake.effects.tenzyu-cli.requires = [
    "common"
    "packages-common"
    "zsh"
    "btop"
    "fastfetch"
    "fzf"
    "git"
    "neovim"
    "starship"
    "tmux"
    "yazi"
    "zoxide"
  ];
}
```

### 8. module を複数ファイルに分解したい場合

`flake.modules.nixos.<feature>` の中で `imports = [ ... ];` を使って構いません。これは **同一 feature 内の実装分解** のための仕組みであり、cross-feature な依存関係は `flake.effects.<feature>.requires` で表現します。`imports` での cross-feature 参照は禁止です。

## アーキテクチャ詳細

この repo の依存解決と projection は次の6要素で完結します。

- **Feature (capability id)**  
  kebab-case の名前。`features.<name> = true;` に並べる単位であり、payload とは独立した識別子。`flake.modules.nixos.<name>` / `flake.modules.homeManager.<name>` / `flake.effects.<name>` の3か所に同名キーで登録される。

- **Module (payload)**  
  `flake.modules.nixos.<name>` と `flake.modules.homeManager.<name>` の中身。`services.*` / `programs.*` / `home.packages` など、NixOS module / home-manager module の **宣言的記述そのもの**。`imports = [ ... ];` を使って同一 feature 内の複数ファイルへ分解して良い。cross-feature な `imports` は禁止。

- **Effect (projection contract)**  
  `flake.effects.<name> = { requires, system, user; }`。
  - `requires` = 依存 feature 名のリスト (graph edge)
  - `system` = system 側 projection rule。`null` (何もしない) / `{}` (collect のみ直接記述) / 関数のいずれか。関数のシグネチャは `{}:`, `{lib}:`, `{lib, ...}:`, `{user, lib}:`, `{user, ...}:`, `args:` すべて受理される。materializer は `builtins.functionArgs` で projection が宣言した引数名を取り出し、`builtins.intersectAttrs` で context (`{ lib; }`) から **宣言された key だけ** を抽出して渡す。positional な `args:` / `_args:` 形式は `{}` を受け取る。context が必要な場合は必ず attrset パターン (`{lib}:` 等) を使う。
  - `user` = user 側 projection rule。`null` / `{}` / 関数のいずれか。関数のシグネチャは `{}:`, `{user}:`, `{user, lib}:`, `{user, ...}:`, `args:` すべて受理される。context からの抽出は system と同じ規約 (`{ user = userRecord; lib = ...; }`)。

  評価結果は `{ config, collect }` 2つ。
  - `config` は **NixOS module attribute set として `imports` に積まれる**ため、module system の merge semantics に従う
  - `collect` は `local.effects.*` へ (submodule merge で) 結合され、最終的に collector module が `nixpkgs.config.*` へ投影する

- **Materializer (projector)**  
  `feature.system` / `feature.users` の2つ。closure を解決し、payload と effect を host module へ materialize する。空の `features`、未知の feature 名は評価時に throw。`feature.users` は内部で **User Factory Aspect** を呼び出して per-user な NixOS user module と Home Manager user module を生成する。

- **User Factory Aspect (per-user module generation)**  
  `flake.lib.userFactory` (`factory-user.nix`)。ユーザー record を受け取り、`users.users.<name>` (`isNormalUser` / `shell` / `extraGroups`) と `home-manager.users.<name>` (`home.username` / `home.homeDirectory` / `home.stateVersion` / `programs.home-manager` / `xdg` / `home.preferXdgDirectories`) を組み立てる1つの NixOS module を返す。`feature.users` が各ユーザーについて1回ずつ呼び出す。host から直接呼ぶ必要はない (Factory Aspect は materializer の内部実装)。

- **Collector (cross-cutting policy final projection)**  
  `flake.modules.nixos.collector` (`collector.nix`)。`local.effects` option を定義し、materializer が merge した値を `nixpkgs.config.*` などの policy 設定へ投影する。`local.effects` schema は `collector.nix` で集中管理。`factory-nixos.nix` が `flake.modules.nixos.collector` を host module へ自動的に組み込む。

この6要素が綺麗に分かれているので、host は `<name>` を選ぶだけで済み、feature 作者は payload だけ・effect だけ・両方を用途に応じて書き分けることができ、policy 軸を増やすときは `collector.nix` の schema と projection rule を1か所ずつ触るだけで済みます。

## Materializer semantics

`feature.system` / `feature.users` は次の規約を守ります。

- **空 `features` / すべて-false は throw**  
  `feature.system: no enabled features` のような評価時エラー。`features = { ssh = false; }` のように有効化された feature が1つもない場合も throw する。意図しない空 projection を防ぐ。

- **未知 feature 名は throw**  
  `flake.modules.<class>.<name>` / `flake.effects.<name>` のいずれにも登録されていない名前は `feature.system: unknown feature '<name>'` / `feature.users.<user>: unknown feature '<name>'` で throw。typo を早期発見する。

- **`requires` の transitive closure を解決**  
  例えば `steam.requires = ["gaming-core"];` で host が `steam = true;` だけを書いた場合、`gaming-core` も closure に取り込まれて projection される。`requires` 側に循環がある場合は、materializer の `resolveClosure` が既に訪れた名前を `acc` で弾くので無限ループにはならないが、**循環そのものは設計ミス** として扱ってください。

- **feature 名は unique + sorted**  
  closure 解決後、`lib.unique` + `lib.naturalSort` で正規化される。`{ steam = true; gaming-core = true; }` の順に書いても materializer は `gaming-core, steam` の順に処理する。

- **NixOS モジュールは host 全体で1回 import**  
  `feature.users` で複数ユーザーが同じ feature を要求しても、`flake.modules.nixos.<feature>` は host imports に1回だけ積まれる (`feature.users` 内部で `systemClosure` を union してから `buildSystemProjection` するため)。一方、`flake.modules.homeManager.<feature>` はユーザーごとに `home-manager.users.<username>.imports` へ積まれる。

- **system effect は host 全体で1回 project**  
  `feature.users` の `systemClosure` (=全ユーザーの closure の union) に対して system effect を1回だけ評価し、`systemProjection` として host の `imports` に積む。

- **Home Manager モジュールは `home-manager.users.<username>.imports` へ**  
  `feature.users` の `users.<name>.imports` 引数もここに追加で積まれる。`imports` は「feature の closure に含めたくない1回限りの手書きモジュール」を配置する。

- **`local.effects.*` は materializer が set し、collector が read**  
  materializer は projection の `collect` を `config.local.effects = <collect>;` を返す module として `imports` に積む (NixOS module system の submodule merge が担当)。collector module はその値を読み、`lib.unique` したうえで `nixpkgs.config.allowUnfreePredicate` / `nixpkgs.config.permittedInsecurePackages` へ投影する。書き手 (materializer) と読み手 (collector) は別モジュールとして直交している。

- **`feature.users` の引数が source of truth**
  host は `feature.users { tenzyu = {...}; };` のようにユーザー spec を **inline で** 渡す。materializer は内部の `userFactory` (User Factory Aspect) を呼び出してユーザーごとの NixOS user module と Home Manager user module を生成する。

- **effect `config` の merge は module system 任せ**  
  effect の `config` は各 effect ごとに `imports` の1モジュールとして積まれるため、`listOf` (concat) / `submodule` (deep merge) / `mkOverride` (priority) など NixOS module system の merge semantics をそのまま享受する。materializer は独自の shallow merge を行わない。

- **cross-feature 依存は `effects.<name>.requires` のみ**  
  `flake.modules.nixos.<name>` 内の `imports = [ ./other-feature.nix ];` のような cross-feature 参照は禁止。feature を跨ぐ依存は必ず `requires` で表現する。これは **「payload の import graph が cross-feature を持たない = feature が合成順序に対して疎になる」** ことを保証する。

- **module の `imports` は単一 feature 内の実装分解専用**  
  大きな feature 定義を `modules/features/<name>/default.nix` などのサブファイルへ分解するのは自由。ただし、サブファイルも `flake.modules.nixos.<name>` 配下の attribute set を返す形にし、cross-feature な import 経路を持たないこと。

## Projection 呼び出し規約

materializer は effect の `system` / `user` を評価する際、`callProjection` ヘルパーを通じて projection function が **宣言した引数だけ** を context から抽出して渡す。

```nix
callProjection = args: projection:
  if projection == null
  then { config = {}; collect = {}; }
  else if builtins.isFunction projection
  then projection (builtins.intersectAttrs (builtins.functionArgs projection) args)
  else projection;
```

- `args` は materializer 側の context。
  - `system` の context は `{ inherit lib; }` のみ。
  - `user` の context は `{ user = userRecord; inherit lib; }`。
- `builtins.functionArgs projection` は projection の **仮引数名** (key) を返す (値は `true`/`false` のマーカーで意味は無い)。
- `builtins.intersectAttrs` は **第1引数の keys と第2引数の keys の共通部分** を抽出し、**値は第2引数のもの** を採用する。
- 結果として、projection が宣言した key だけが context から取り出されて関数に渡される。projection が受け取れない key は無視される。

受理される signature と、引数の実体:

| signature | `system` 評価時の `args` 実体 | `user` 評価時の `args` 実体 |
| --- | --- | --- |
| `null` (未設定) | — (空 `{config={}; collect={};}`) | — (空 `{config={}; collect={};}`) |
| `{}` (set form) | — (result として直接使用) | — (result として直接使用) |
| `_args: result` (positional) | `{}` (`functionArgs` が空 attrset を返すため) | `{}` |
| `args: result` (positional) | `{}` | `{}` |
| `{}: result` (no-arg pattern) | `{}` | `{}` |
| `{ lib }: result` | `{ lib = <lib>; }` | `{ lib = <lib>; }` |
| `{ lib, ... }: result` | `{ lib = <lib>; }` (rest は無視される) | `{ lib = <lib>; }` |
| `{ user }: result` (user only) | n/a (system context には `user` が無い) | `{ user = <userRecord>; }` |
| `{ user, ... }: result` | n/a | `{ user = <userRecord>; }` |
| `{ user, lib }: result` | n/a | `{ user = <userRecord>; lib = <lib>; }` |

**`args:` / `_args:` / `x:` 形式の positional 関数は現在の実装では `{}` を受け取る** (`builtins.functionArgs` が positional 関数に対して空 attrset を返すため、intersectAttrs が空を返す)。context が必要な場合は必ず `{lib}:` / `{user}:` のような **attrset パターン** を使うこと。

## 非目標

このnixfilesは、汎用フレームワークや他人向けテンプレートを目指していません。

優先しているのは次の性質です。

- 自分のホスト構成を素早く読めること
- 新しい機能を小さなファイルとして足せること
- 例外的なpackage policyを追跡できること
- NixOSとhome-managerの重複を減らしすぎず、必要な場所で明示できること
- feature 間の依存関係を `flake.effects.<name>.requires` で一箇所に集めて追跡できること

抽象化は、実際の重複や環境差分を減らす場合にだけ導入します。

## まとめ

このrepoは、次の一文で表せます。

> ホストは薄く、機能は小さく、payload は `flake.modules`、policy は `flake.effects`、依存は `requires`、projection は materializer + collector。

そのため、読む順番は次がおすすめです。

1. `flake.nix`
2. `modules/flake/flake-parts.nix`
3. `modules/flake/factory-nixos.nix` (collector module の注入)
4. `modules/flake/collector.nix` (`local.effects` schema)
5. `modules/flake/feature.nix` (materializer)
6. `modules/00-hosts/<host>/configuration.nix`
7. そこから参照されている`modules/nixos/`、`modules/home/`、`modules/features/`の各機能

## Gaming runtime

This repo keeps gaming optimizations explicit instead of hiding them behind global state。

`gaming-core` を有効化すると、以下のコマンドが user の `home.packages` から使えるようになります。

| コマンド | 役割 |
| --- | --- |
| `game-scope %command%` | `gamemoderun` + `gamescope` をまとめて起動する汎用ラッパー。Steam の per-game launch options に指定する。 |

`hyprland-gaming-mode` を有効化すると、以下のコマンドが追加されます。

| コマンド | 役割 |
| --- | --- |
| `hypr-gaming-mode on\|off` | Hyprland の animation / blur / shadow / gap / vrr などを一括でゲーム向けプロファイルに切り替える。GameMode 起動時の `start` / `end` hook もこの feature が担う。 |

`osu-lazer` を有効化すると `osu-lazer` / `osu-lazer-raw` の2つのラッパーが `home.packages` から使えるようになります。

- `osu-lazer` は `gamemoderun` 経由で `osu-lazer-bin` を起動する。`hypr-gaming-mode` が有効なら on/off を連動させる。
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
