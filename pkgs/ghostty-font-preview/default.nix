{ writeShellApplication, fzf, ghostty, fastfetch }:

writeShellApplication {
  name = "ghostty-font-preview";
  runtimeInputs = [ fzf ghostty fastfetch ];
  text = ''
    # Ghostty Font Preview - Interactive font selector with live preview
    #
    # Uses FZF to browse available Ghostty fonts and spawns a preview
    # terminal with fastfetch to show each font in action.

    # Create a temp preview script to avoid quoting issues with FZF
    PREVIEW_SCRIPT=$(mktemp)
    cat > "$PREVIEW_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash
font="$*"
pkill -f "ghostty.*font-preview-window" 2>/dev/null || true
ghostty --title="font-preview-window" --font-family="$font" -e sh -c "fastfetch; echo; echo \"Font: $font\"; read -n 1" 2>&1 &
EOFSCRIPT
    chmod +x "$PREVIEW_SCRIPT"

    cleanup() {
      pkill -f "ghostty.*font-preview-window" 2>/dev/null || true
      rm -f "$PREVIEW_SCRIPT"
    }
    trap cleanup EXIT

    # Get font family names (unindented lines from ghostty +list-fonts)
    get_font_families() {
      ghostty +list-fonts | grep -E '^[^ ]' | sort -u
    }

    # Main: pipe fonts to fzf with preview
    selected=$(get_font_families | fzf \
      --header="Select a font (preview spawns in new window)" \
      --preview-window=hidden \
      --bind "change:execute-silent($PREVIEW_SCRIPT {})" \
      --bind "up:up+execute-silent($PREVIEW_SCRIPT {})" \
      --bind "down:down+execute-silent($PREVIEW_SCRIPT {})")

    # Cleanup and print result
    cleanup

    if [ -n "$selected" ]; then
      echo "$selected"
    fi
  '';
}
