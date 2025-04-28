{ pkgs, ... }: {
  home.packages = with pkgs; [
    nerdfonts # for devicons
    nixd # nix-lsp
  ];
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      " Basic settings
      set number
      set tabstop     =4
      set softtabstop =4
      set shiftwidth  =4
      set expandtab

      " Set this variable to 1 to fix files when you save them.
      let g:ale_fix_on_save = 1
      let g:go_fmt_fail_silently = 1 " https://github.com/dense-analysis/ale/issues/609

      " NERDTree
      nnoremap <leader>n :NERDTreeFocus<CR>
      nnoremap <C-n> :NERDTree<CR>
      nnoremap <C-t> :NERDTreeToggle<CR>
      nnoremap <C-f> :NERDTreeFind<CR>
      autocmd VimEnter * NERDTree | wincmd p

      " SOPS
      nnoremap <leader>ef :SopsEncrypt<CR>
      nnoremap <leader>df :SopsDecrypt<CR>
    '';
    plugins = with pkgs.vimPlugins; [
        leap-nvim
        vim-nix
        vim-go
        vim-ruby
        vim-startify
        nerdtree
        nerdtree-git-plugin
        vim-devicons
        nvim-sops
        fzfWrapper
        which-key-nvim
        vim-better-whitespace
        vim-fugitive
        vim-surround
        nvim-cmp
        ale
        vim-indent-guides
    ];
  };
}
