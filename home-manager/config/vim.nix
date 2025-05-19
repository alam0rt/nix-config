{pkgs, ...}: {
  home.packages = with pkgs; [
    # nerdfonts # for devicons # broken with 25.05
    nixd # nix-lsp
    gofumpt # stricter gofmt
    yaml-language-server
    bash-language-server
    dockerfile-language-server-nodejs
    nodePackages.vscode-json-languageserver # json
    jsonnet-language-server
    ruby-lsp
    openscad-lsp
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
      nnoremap <C-f> :FZF<CR>

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

        vim.lsp.config['jsonnetls'] = {
          cmd = { 'jsonnet-language-server', '--lint', '-J', 'kubernetes', '-J', 'cicd-toolkit/lib', '-J', 'cicd-toolkit/vendor/cicd-toolkit/jsonnet', '-J', 'cicd-toolkit/vendor' },
          capabilities = capabilities,
          filetypes = { 'jsonnet' },
          root_markers = { '.git' },
        }
        vim.lsp.enable('jsonnetls')

        require('lspconfig')['nixd'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['gopls'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['yamlls'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['ruby_lsp'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['rust_analyzer'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['bashls'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['dockerls'].setup {
          capabilities = capabilities
        }
        require('lspconfig')['jsonls'].setup {
          capabilities = capabilities,
          -- Use correct binary as per Nix
          cmd = {'vscode-json-languageserver', '--stdio'},
        }
        require('lspconfig')['openscad_lsp'].setup {
          capabilities = capabilities
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
      fzfWrapper
      which-key-nvim
      vim-fugitive
      vim-surround
      vim-startify
      vim-jsonnet

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
