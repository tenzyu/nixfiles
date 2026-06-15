{
  flake.modules.homeManager.zed-editor = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.zed-editor.enable {
      programs.zed-editor = {
        enable = true;
        package = pkgs.zed-editor;

        extraPackages = with pkgs; [
          bun
          vtsls
          tailwindcss-language-server
          eslint
          prettier
          biome

          rust-analyzer
          rustfmt
          clippy
          cargo
          rustc
          cargo-tauri

          nixd
          nixfmt-rfc-style

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

                cargo = {
                  allTargets = false;
                };

                check = {
                  workspace = false;
                };
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
  };
}
