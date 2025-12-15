{ writeShellApplication, fzf, ghostty, fastfetch }:

writeShellApplication {
  name = "ghostty-font-preview";
  runtimeInputs = [ fzf ghostty fastfetch ];
  text = ''
    # Ghostty Font Preview - Interactive font selector with live preview
    #
    # Uses FZF to browse available Ghostty fonts and spawns a preview
    # terminal with fastfetch to show each font in action.

    cleanup() {
      # Kill any lingering preview windows
      pkill -f "ghostty.*--class=font-preview" 2>/dev/null || true
    }
    trap cleanup EXIT

    # Get font family names (unindented lines from ghostty +list-fonts)
    get_font_families() {
      ghostty +list-fonts | grep -E '^[^ ]' | sort -u
    }

    # Preview function - launches ghostty with selected font
    preview_font() {
      local font="$1"
      # Kill previous preview window if any
      pkill -f "ghostty.*--class=font-preview" 2>/dev/null || true
      # Launch new preview window (non-blocking)
      ghostty --class=font-preview --font-family="$font" -e sh -c "fastfetch; echo ''; echo 'Font: $font'; echo 'Press any key to close...'; read -n 1" &
    }

    export -f preview_font

    # Main: pipe fonts to fzf with preview
    selected=$(get_font_families | fzf \
      --header="Select a font (preview spawns in new window)" \
      --preview="bash -c 'preview_font {}'"\
      --preview-window=hidden \
      --bind="change:execute-silent(bash -c 'preview_font {}')" \
      --bind="up:up+execute-silent(bash -c 'preview_font {}')" \
      --bind="down:down+execute-silent(bash -c 'preview_font {}')")

    # Cleanup and print result
    cleanup

    if [ -n "$selected" ]; then
      echo "$selected"
    fi
  '';
}
