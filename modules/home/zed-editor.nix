{
  flake.modules.homeManager.zedEditor = {
    pkgs,
    lib,
    ...
  }: {
    programs.zed-editor = {
      enable = true;
      package = pkgs.zed-editor;

      extraPackages = with pkgs; [
        # TS
        bun
        vtsls
        tailwindcss-language-server
        eslint
        prettier
        biome

        # Rust / Tauri
        rust-analyzer
        rustfmt
        clippy
        cargo
        rustc
        cargo-tauri

        # Nix
        nixd
        nixfmt-rfc-style

        # Tauri / native build helpers
        pkg-config
        openssl
        webkitgtk_4_1
        librsvg
      ];

      installRemoteServer = true;

      extensions = [
        "nix"
        "toml"
      ];

      userSettings = {
        auto_update = false;
        telemetry = {
          metrics = false;
        };

        # direnv + flake/devShell を使うならかなり重要。
        # Zed 側がプロジェクトごとの devShell を拾える。
        load_direnv = "shell_hook";

        languages = {
          "TypeScript" = {
            language_servers = ["vtsls" "tailwindcss-language-server" "..."];
            formatter = "prettier";
            format_on_save = "on";
          };

          "TSX" = {
            language_servers = ["vtsls" "tailwindcss-language-server" "..."];
            formatter = "prettier";
            format_on_save = "on";
          };

          "JavaScript" = {
            language_servers = ["vtsls" "tailwindcss-language-server" "..."];
            formatter = "prettier";
            format_on_save = "on";
          };

          "Rust" = {
            formatter = "language_server";
            format_on_save = "on";
          };

          "Nix" = {
            language_servers = ["nixd" "..."];
            formatter = {
              external = {
                command = "nixfmt";
                arguments = ["--strict" "--filename" "{buffer_path}"];
              };
            };
            format_on_save = "on";
          };
        };

        lsp = {
          vtsls = {
            settings = {
              typescript = {
                tsserver = {
                  # i5-10210U + RAM 少なめなら 4096〜8092 くらいで様子見。
                  maxTsServerMemory = 4096;
                };
              };
              javascript = {
                tsserver = {
                  maxTsServerMemory = 4096;
                };
              };
            };
          };

          "rust-analyzer" = {
            binary = {
              path = lib.getExe pkgs.rust-analyzer;
              arguments = [];
            };

            initialization_options = {
              rust = {
                analyzerTargetDir = true;
              };

              # ノートPCで巨大 workspace を開くなら軽量化寄り。
              cargo = {
                allTargets = false;
              };

              check = {
                workspace = false;
              };

              # 重ければ false にする。
              # checkOnSave = false;
            };
          };

          "tailwindcss-language-server" = {
            settings = {
              classFunctions = ["clsx" "cva" "cx" "cn"];
            };
          };
        };
        terminal = {
          working_directory = "current_project_directory";
          shell = "system";
        };
      };
    };
  };
}
