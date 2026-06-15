{
  flake.modules.homeManager.zed-editor = {
    config,
    lib,
    pkgs,
    ...
  }: let
    flakePath = config.local.context.flakePath;

    nixosConfigurationName =
      if config.local.context.nixosConfigurationName != null
      then config.local.context.nixosConfigurationName
      else config.local.context.hostName;

    userName = config.local.user.name;

    flakeExpr = "builtins.getFlake \"${flakePath}\"";

    nixosOptionsExpr = "(${flakeExpr}).nixosConfigurations.\"${nixosConfigurationName}\".options";

    nixosLocalFeaturesOptionsExpr = "(${nixosOptionsExpr}).local.features";

    nixosLocalUserOptionsExpr = "(${nixosOptionsExpr}).local.users.type.getSubOptions [ \"${userName}\" ]";

    nixosLocalUserFeaturesOptionsExpr = "(${nixosLocalUserOptionsExpr}).features";

    embeddedHomeUserOptionsExpr = "(${nixosOptionsExpr}).\"home-manager\".users.type.getSubOptions [ \"${userName}\" ]";

    embeddedHomeUserLocalFeaturesOptionsExpr = "(${embeddedHomeUserOptionsExpr}).local.features";

    nixosWrappedCurrentModuleOptionsExpr = ''
      let
        options = ${nixosOptionsExpr};
        localFeaturesOptions = ${nixosLocalFeaturesOptionsExpr};
        userOptions = ${nixosLocalUserOptionsExpr};
        userFeatureOptions = ${nixosLocalUserFeaturesOptionsExpr};
      in {
        configurations.nixos."${nixosConfigurationName}".module = options;
        configurations.nixos."${nixosConfigurationName}".module.local.features = localFeaturesOptions;
        configurations.nixos."${nixosConfigurationName}".module.local.users."${userName}" = userOptions;
        configurations.nixos."${nixosConfigurationName}".module.local.users."${userName}".features = userFeatureOptions;
      }
    '';
  in {
    config = lib.mkIf config.local.features.zed-editor.enable {
      programs.zed-editor = {
        enable = true;
        package = pkgs.zed-editor;

        mutableUserSettings = false;
        installRemoteServer = true;

        extraPackages = with pkgs; [
          # JS / TS / React / Tailwind
          nodejs
          bun
          typescript
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
          alejandra

          # Native / Tauri dependencies often needed by projects
          pkg-config
          openssl
          webkitgtk_4_1
          librsvg
        ];

        extensions = [
          "nix"
          "toml"
          "dockerfile"
        ];

        userSettings = {
          auto_update = false;
          vim_mode = true;

          telemetry = {
            metrics = false;
          };

          load_direnv = "shell_hook";

          show_completions_on_input = true;
          show_completion_documentation = true;
          show_edit_predictions = true;
          lsp_insert_mode = "replace_suffix";

          inlay_hints = {
            enabled = true;
            show_type_hints = true;
            show_parameter_hints = true;
            show_other_hints = true;
            show_background = false;
          };

          languages = {
            "TypeScript" = {
              language_servers = [
                "vtsls"
                "tailwindcss-language-server"
                "..."
              ];

              formatter = {
                external = {
                  command = "prettier";
                  arguments = [
                    "--stdin-filepath"
                    "{buffer_path}"
                  ];
                };
              };

              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };

            "TSX" = {
              language_servers = [
                "vtsls"
                "tailwindcss-language-server"
                "..."
              ];

              formatter = {
                external = {
                  command = "prettier";
                  arguments = [
                    "--stdin-filepath"
                    "{buffer_path}"
                  ];
                };
              };

              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };

            "JavaScript" = {
              language_servers = [
                "vtsls"
                "tailwindcss-language-server"
                "..."
              ];

              formatter = {
                external = {
                  command = "prettier";
                  arguments = [
                    "--stdin-filepath"
                    "{buffer_path}"
                  ];
                };
              };

              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };

            "JSX" = {
              language_servers = [
                "vtsls"
                "tailwindcss-language-server"
                "..."
              ];

              formatter = {
                external = {
                  command = "prettier";
                  arguments = [
                    "--stdin-filepath"
                    "{buffer_path}"
                  ];
                };
              };

              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };

            "Rust" = {
              language_servers = [
                "rust-analyzer"
                "..."
              ];

              formatter = "language_server";
              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };

            "Nix" = {
              language_servers = [
                "nixd"
                "!nil"
              ];

              formatter = {
                external = {
                  command = "alejandra";
                  arguments = [];
                };
              };

              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };

            "TOML" = {
              language_servers = ["..."];
              format_on_save = "on";
              show_completions_on_input = true;
              show_completion_documentation = true;
            };
          };

          lsp = {
            nixd = {
              binary = {
                path = lib.getExe pkgs.nixd;
                arguments = [];
              };

              settings = {
                nixd = {
                  formatting = {
                    command = ["alejandra"];
                  };

                  options = {
                    nixos-current = {
                      expr = nixosOptionsExpr;
                    };

                    nixos-current-local-features = {
                      expr = nixosLocalFeaturesOptionsExpr;
                    };

                    nixos-current-local-user = {
                      expr = nixosLocalUserOptionsExpr;
                    };

                    nixos-current-local-user-features = {
                      expr = nixosLocalUserFeaturesOptionsExpr;
                    };

                    nixos-current-wrapper-module = {
                      expr = nixosWrappedCurrentModuleOptionsExpr;
                    };

                    embedded-home-current-user = {
                      expr = embeddedHomeUserOptionsExpr;
                    };

                    embedded-home-current-user-local-features = {
                      expr = embeddedHomeUserLocalFeaturesOptionsExpr;
                    };
                  };
                };
              };
            };

            vtsls = {
              binary = {
                path = lib.getExe pkgs.vtsls;
                arguments = [];
              };

              settings = {
                typescript = {
                  tsserver = {
                    maxTsServerMemory = 4096;
                  };

                  preferences = {
                    includePackageJsonAutoImports = "on";
                    includeCompletionsForModuleExports = true;
                    includeCompletionsForImportStatements = true;
                    includeCompletionsWithSnippetText = true;
                    includeAutomaticOptionalChainCompletions = true;
                    includeCompletionsWithInsertText = true;
                  };

                  inlayHints = {
                    parameterNames = {
                      enabled = "literals";
                    };

                    parameterTypes = {
                      enabled = true;
                    };

                    variableTypes = {
                      enabled = true;
                    };

                    propertyDeclarationTypes = {
                      enabled = true;
                    };

                    functionLikeReturnTypes = {
                      enabled = true;
                    };

                    enumMemberValues = {
                      enabled = true;
                    };
                  };
                };

                javascript = {
                  tsserver = {
                    maxTsServerMemory = 4096;
                  };

                  preferences = {
                    includePackageJsonAutoImports = "on";
                    includeCompletionsForModuleExports = true;
                    includeCompletionsForImportStatements = true;
                    includeCompletionsWithSnippetText = true;
                    includeAutomaticOptionalChainCompletions = true;
                    includeCompletionsWithInsertText = true;
                  };

                  inlayHints = {
                    parameterNames = {
                      enabled = "literals";
                    };

                    parameterTypes = {
                      enabled = true;
                    };

                    variableTypes = {
                      enabled = true;
                    };

                    propertyDeclarationTypes = {
                      enabled = true;
                    };

                    functionLikeReturnTypes = {
                      enabled = true;
                    };

                    enumMemberValues = {
                      enabled = true;
                    };
                  };
                };
              };
            };

            "tailwindcss-language-server" = {
              binary = {
                path = lib.getExe pkgs.tailwindcss-language-server;
                arguments = [];
              };

              settings = {
                tailwindCSS = {
                  classFunctions = [
                    "clsx"
                    "cva"
                    "cx"
                    "cn"
                  ];

                  includeLanguages = {
                    typescript = "javascript";
                    typescriptreact = "javascript";
                    javascript = "javascript";
                    javascriptreact = "javascript";
                  };
                };

                experimental = {
                  classRegex = [
                    [
                      "cva\\(([^)]*)\\)"
                      "[\"'`]([^\"'`]*).*?[\"'`]"
                    ]
                    [
                      "cn\\(([^)]*)\\)"
                      "[\"'`]([^\"'`]*).*?[\"'`]"
                    ]
                    [
                      "clsx\\(([^)]*)\\)"
                      "[\"'`]([^\"'`]*).*?[\"'`]"
                    ]
                  ];
                };
              };
            };

            "rust-analyzer" = {
              binary = {
                path = lib.getExe pkgs.rust-analyzer;
                arguments = [];
              };

              initialization_options = {
                cargo = {
                  allTargets = false;
                  features = "all";
                };

                check = {
                  command = "clippy";
                  workspace = false;
                };

                procMacro = {
                  enable = true;
                };

                completion = {
                  callable = {
                    snippets = "add_parentheses";
                  };

                  postfix = {
                    enable = true;
                  };

                  fullFunctionSignatures = {
                    enable = true;
                  };
                };

                inlayHints = {
                  bindingModeHints = {
                    enable = true;
                  };

                  chainingHints = {
                    enable = true;
                  };

                  closingBraceHints = {
                    enable = true;
                  };

                  closureReturnTypeHints = {
                    enable = "always";
                  };

                  lifetimeElisionHints = {
                    enable = "skip_trivial";
                    useParameterNames = true;
                  };

                  parameterHints = {
                    enable = true;
                  };

                  typeHints = {
                    enable = true;
                  };
                };
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
