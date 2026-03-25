{pkgs, ...}: {
  programs.neovim = {
    enable = true;

    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;

    extraPackages = with pkgs; [
      fd
      ripgrep
      stylua
      nixd
      lua-language-server
      pyright
      typescript-language-server
      vscode-langservers-extracted
    ];

    plugins = with pkgs.vimPlugins; [
      catppuccin-nvim
      plenary-nvim
      nui-nvim
      nvim-web-devicons
      telescope-nvim
      telescope-ui-select-nvim
      which-key-nvim
      neo-tree-nvim
      trouble-nvim
      gitsigns-nvim
      lualine-nvim
      fidget-nvim
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      luasnip
      cmp_luasnip
      friendly-snippets
      vim-nix
      nvim-treesitter.withAllGrammars
    ];

    extraConfig = ''
      let mapleader = " "
      let maplocalleader = " "

      set number
      set relativenumber
      set mouse=a
      set clipboard=unnamedplus
      set ignorecase
      set smartcase
      set hlsearch
      set incsearch
      set termguicolors
      set signcolumn=yes
      set updatetime=200
      set splitright
      set splitbelow
      set tabstop=2
      set shiftwidth=2
      set softtabstop=2
      set expandtab
      set smartindent
      set cursorline
      set scrolloff=4
      set sidescrolloff=8
      set nowrap
      set completeopt=menu,menuone,noselect

      colorscheme catppuccin-mocha

      highlight Normal guibg=NONE ctermbg=NONE
      highlight NormalNC guibg=NONE ctermbg=NONE
      highlight SignColumn guibg=NONE ctermbg=NONE
      highlight NormalFloat guibg=NONE ctermbg=NONE
      highlight FloatBorder guibg=NONE ctermbg=NONE
      highlight Pmenu guibg=NONE ctermbg=NONE

      nnoremap <silent> <Esc> <cmd>nohlsearch<CR>
      nnoremap <silent> <leader>w <cmd>write<CR>
      nnoremap <silent> <leader>q <cmd>quit<CR>
      nnoremap <silent> <leader>h <C-w>h
      nnoremap <silent> <leader>j <C-w>j
      nnoremap <silent> <leader>k <C-w>k
      nnoremap <silent> <leader>l <C-w>l
      nnoremap <silent> <leader>e <cmd>Neotree toggle filesystem reveal left<CR>
      nnoremap <silent> <leader>ff <cmd>Telescope find_files<CR>
      nnoremap <silent> <leader>fg <cmd>Telescope live_grep<CR>
      nnoremap <silent> <leader>fb <cmd>Telescope buffers<CR>
      nnoremap <silent> <leader>fr <cmd>Telescope oldfiles<CR>
      nnoremap <silent> <leader>fs <cmd>Telescope lsp_document_symbols<CR>
      nnoremap <silent> <leader>xx <cmd>Trouble diagnostics toggle<CR>
      nnoremap <silent> <leader>xw <cmd>Trouble diagnostics toggle filter.buf=0<CR>
      nnoremap <silent> <leader>gr <cmd>Telescope lsp_references<CR>
      nnoremap <silent> <leader>gs <cmd>Telescope git_status<CR>
      nnoremap <silent> <leader>gg <cmd>terminal lazygit<CR>
    '';

    extraLuaConfig = ''
      local map = vim.keymap.set

      local function smart_ctrl_w()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local line = vim.api.nvim_get_current_line()
        local before = line:sub(1, cursor[2])
        local patterns = {
          "\\s\\+$",
          "[0-9A-Za-z_./-]\\+$",
          "[ぁ-んァ-ンー一-龥々]\\+$",
          "[[:punct:]]\\+$",
          ".$",
        }

        for _, pattern in ipairs(patterns) do
          local match = vim.fn.matchstr(before, pattern)
          if match ~= "" then
            return vim.api.nvim_replace_termcodes(
              string.rep("<BS>", vim.fn.strchars(match)),
              true,
              false,
              true
            )
          end
        end

        return vim.api.nvim_replace_termcodes("<C-w>", true, false, true)
      end

      map("i", "<C-w>", smart_ctrl_w, { expr = true, silent = true, desc = "smart backward delete" })

      local japanese_word = "\\v[ぁ-んァ-ンー一-龥々]+|[0-9A-Za-z_./-]+|[^[:space:]]"

      local function search_word(flags)
        vim.fn.search(japanese_word, flags)
      end

      map("n", "]w", function()
        search_word("W")
      end, { silent = true, desc = "next word chunk" })

      map("n", "[w", function()
        search_word("bW")
      end, { silent = true, desc = "previous word chunk" })

      require("fidget").setup({})

      require("gitsigns").setup({
        current_line_blame = false,
      })

      require("lualine").setup({
        options = {
          theme = "catppuccin",
          globalstatus = true,
          section_separators = "",
          component_separators = "",
        },
      })

      require("which-key").setup({})

      require("neo-tree").setup({
        close_if_last_window = true,
        popup_border_style = "rounded",
        enable_git_status = true,
        filesystem = {
          filtered_items = {
            hide_dotfiles = false,
            hide_gitignored = false,
          },
          follow_current_file = {
            enabled = true,
          },
          use_libuv_file_watcher = true,
        },
        window = {
          width = 34,
        },
      })

      require("telescope").setup({
        defaults = {
          layout_strategy = "horizontal",
          layout_config = {
            prompt_position = "top",
          },
          sorting_strategy = "ascending",
        },
        pickers = {
          find_files = {
            hidden = true,
          },
        },
        extensions = {
          ["ui-select"] = require("telescope.themes").get_dropdown({}),
        },
      })
      require("telescope").load_extension("ui-select")

      require("trouble").setup({})

      require("nvim-treesitter.configs").setup({
        highlight = { enable = true },
        indent = { enable = true },
      })

      local cmp = require("cmp")
      local luasnip = require("luasnip")

      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
          ["<Tab>"] = cmp.mapping.select_next_item(),
          ["<S-Tab>"] = cmp.mapping.select_prev_item(),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
      })

      cmp.setup.cmdline("/", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          { name = "cmdline" },
        }),
      })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local on_attach = function(_, bufnr)
        local buffer_map = function(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
        end

        buffer_map("n", "gd", vim.lsp.buf.definition, "go to definition")
        buffer_map("n", "gD", vim.lsp.buf.declaration, "go to declaration")
        buffer_map("n", "gr", vim.lsp.buf.references, "list references")
        buffer_map("n", "gi", vim.lsp.buf.implementation, "go to implementation")
        buffer_map("n", "K", vim.lsp.buf.hover, "hover")
        buffer_map("n", "<leader>rn", vim.lsp.buf.rename, "rename symbol")
        buffer_map("n", "<leader>ca", vim.lsp.buf.code_action, "code action")
        buffer_map("n", "<leader>f", function()
          vim.lsp.buf.format({ async = true })
        end, "format buffer")
      end

      local lspconfig = require("lspconfig")
      local servers = {
        nixd = {},
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = {
                globals = { "vim" },
              },
            },
          },
        },
        pyright = {},
        ts_ls = {},
        html = {},
        cssls = {},
        jsonls = {},
      }

      for server, server_opts in pairs(servers) do
        server_opts.capabilities = capabilities
        server_opts.on_attach = on_attach
        lspconfig[server].setup(server_opts)
      end
    '';
  };
}
