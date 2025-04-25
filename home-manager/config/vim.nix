{ pkgs, ... }: {
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      set number

      set tabstop     =4
      set softtabstop =4
      set shiftwidth  =4
      set expandtab

      nnoremap <leader>n :NERDTreeFocus<CR>
      nnoremap <C-n> :NERDTree<CR>
      nnoremap <C-t> :NERDTreeToggle<CR>
      nnoremap <C-f> :NERDTreeFind<CR>
      autocmd VimEnter * NERDTree
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
    ];
  };
}
