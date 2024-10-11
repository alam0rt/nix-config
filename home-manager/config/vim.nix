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

    '';
    plugins = [
        {
            plugin = pkgs.vimPlugins.vim-sneak;
            config = "let g:sneak#label = 1";
        }
    ];
  };
}
