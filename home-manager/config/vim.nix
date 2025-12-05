{pkgs, ...}: {
  home.packages = with pkgs; [
    # nerdfonts # for devicons # broken with 25.05
    nixd # nix-lsp
    gofumpt # stricter gofmt
    yaml-language-server
    bash-language-server
    dockerfile-language-server
    nodePackages.vscode-json-languageserver # json
    jsonnet-language-server
    ruby-lsp
  ];
  programs.neovim = {
    enable = true;
    package = pkgs.unstable.neovim-unwrapped; # want 0.11+
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      " Basic settings
      set number
      set tabstop     =4
      set softtabstop =4
      set shiftwidth  =4
      set expandtab

      " FZF
      nnoremap <C-f> :Files<CR>
      nnoremap <C-s> :RG<CR>

      " vim-go
      let g:go_fmt_command="gopls"
      let g:go_gopls_gofumpt=1

      " NERDTree
      nnoremap <leader>n :NERDTreeFocus<CR>
      nnoremap <C-n> :NERDTree<CR>
      nnoremap <C-t> :NERDTreeToggle<CR>

      " SOPS
      nnoremap <leader>ef :SopsEncrypt<CR>
      nnoremap <leader>df :SopsDecrypt<CR>

      " Custom
      nnoremap <leader>t :split term://zsh<CR>

      " leap.nvim
      " https://github.com/ggandor/leap.nvim?tab=readme-ov-file#installation
      lua <<EOF
        vim.keymap.set({'n', 'x', 'o'}, 's', '<Plug>(leap)')
        vim.keymap.set('n',             'S', '<Plug>(leap-from-window)')
      EOF

      " nvim-cmp
      lua <<EOF
        -- Set up nvim-cmp.
        local cmp = require'cmp'

        cmp.setup({
          snippet = {
            expand = function(args)
              vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
            end,
          },
          window = {
            completion = cmp.config.window.bordered(),
            documentation = cmp.config.window.bordered(),
          },
          mapping = cmp.mapping.preset.insert({
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-e>'] = cmp.mapping.abort(),
            ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
          }),
          sources = cmp.config.sources({
            { name = 'nvim_lsp' },
            { name = 'vsnip' }, -- For vsnip users.
          }, {
            { name = 'buffer' },
          })
        })

        -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
        cmp.setup.cmdline({ '/', '?' }, {
          mapping = cmp.mapping.preset.cmdline(),
          sources = {
            { name = 'buffer' }
          }
        })

        -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
        cmp.setup.cmdline(':', {
          mapping = cmp.mapping.preset.cmdline(),
          sources = cmp.config.sources({
            { name = 'path' }
          }, {
            { name = 'cmdline' }
          }),
          matching = { disallow_symbol_nonprefix_matching = false }
        })

        -- Set up lspconfig.
        local capabilities = require('cmp_nvim_lsp').default_capabilities()

        vim.lsp.enable('jsonnetls')
        vim.lsp.config['jsonnetls'] = {
          cmd = { 'jsonnet-language-server', '--lint', '-J', 'kubernetes', '-J', 'cicd-toolkit/lib', '-J', 'cicd-toolkit/vendor/cicd-toolkit/jsonnet', '-J', 'cicd-toolkit/vendor' },
          capabilities = capabilities,
          filetypes = { 'jsonnet' },
          root_markers = { '.git' },
        }

        vim.lsp.enable('nixd')
        vim.lsp.config['nixd'] = {
          cmd = { 'nixd' },
          capabilities = capabilities,
          filetypes = { 'nix' },
          root_markers = { '.git', 'default.nix', 'shell.nix', 'flake.nix' },
        }

        vim.lsp.enable('gopls')
        vim.lsp.config['gopls'] = {
          cmd = { 'gopls' },
          capabilities = capabilities,
          filetypes = { 'go', 'gomod', 'gosum', 'gowork' },
          root_markers = { '.git', 'go.mod' },
        }

        vim.lsp.enable('yamlls')
        vim.lsp.config['yamlls'] = {
          cmd = { 'yaml-language-server', '--stdio' },
          capabilities = capabilities,
          filetypes = { 'yaml' },
          root_markers = { '.git', '.yamllint.yml', 'yamllint.yml', '.yaml-lint.yml', 'yaml-lint.yml' },
        }

        vim.lsp.enable('ruby_lsp')
        vim.lsp.config['ruby_lsp'] = {
          cmd = { 'ruby-lsp' },
          capabilities = capabilities,
          filetypes = { 'ruby' },
          root_markers = { '.git', 'Gemfile' },
        }

        vim.lsp.enable('rust_analyzer')
        vim.lsp.config['rust_analyzer'] = {
          cmd = { 'rust-analyzer' },
          capabilities = capabilities,
          filetypes = { 'rust' },
          root_markers = { '.git', 'Cargo.toml' },
        }

        vim.lsp.enable('bashls')
        vim.lsp.config['bashls'] = {
          cmd = { 'bash-language-server', 'start' },
          capabilities = capabilities,
          filetypes = { 'sh', 'bash' },
          root_markers = { '.git', '.bashrc', '.bash_profile', '.profile' },
        }

        vim.lsp.enable('dockerls')
        vim.lsp.config['dockerls'] = {
          cmd = { 'docker-langserver', '--stdio' },
          capabilities = capabilities,
          filetypes = { 'dockerfile' },
          root_markers = { '.git', 'Dockerfile' },
        }

        vim.lsp.enable('jsonls')
        vim.lsp.config['jsonls'] = {
          cmd = { 'vscode-json-languageserver', '--stdio' },
          capabilities = capabilities,
          filetypes = { 'json' },
          root_markers = { '.git', 'package.json', 'tsconfig.json', '.eslintrc', '.prettierrc' },
        }
      EOF
    '';
    plugins = with pkgs.vimPlugins; [
      # navigation
      leap-nvim

      # languages
      vim-nix
      vim-go
      vim-ruby

      # core
      nerdtree
      nerdtree-git-plugin
      fzf-vim
      which-key-nvim
      vim-fugitive
      vim-surround
      vim-startify
      vim-jsonnet
      vimagit

      # secretz
      nvim-sops

      # visual
      vim-devicons
      vim-indent-guides
      vim-better-whitespace

      # lsp / cmp
      nvim-lspconfig
      nvim-cmp
      cmp-path
      cmp-buffer
      cmp-cmdline
      cmp-nvim-lsp

      # snippet support
      vim-vsnip
      cmp-vsnip

      # ai
      copilot-vim

      # treesitter
      nvim-treesitter
      nvim-treesitter-parsers.go
      nvim-treesitter-parsers.gomod
      nvim-treesitter-parsers.gosum
      nvim-treesitter-parsers.ruby
      nvim-treesitter-parsers.rust
      nvim-treesitter-parsers.yaml
      nvim-treesitter-parsers.jsonnet
      nvim-treesitter-parsers.json
      nvim-treesitter-parsers.bash
    ];
  };
}
