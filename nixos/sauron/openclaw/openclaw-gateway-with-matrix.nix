{ lib
, stdenv
, basePackage
}:

# Simple wrapper that adds @vector-im/matrix-bot-sdk to openclaw-gateway
# The Matrix plugin (@openclaw/matrix) expects this dependency to be available
basePackage.overrideAttrs (oldAttrs: {
  postInstall = (oldAttrs.postInstall or "") + ''
    # The Matrix plugin requires @vector-im/matrix-bot-sdk but it's not in the base package.
    # Following the pattern from upstream gateway-install.sh which does similar workarounds
    # for strip-ansi, combined-stream, and hasown dependencies.
    
    echo "Adding @vector-im/matrix-bot-sdk dependency for Matrix plugin support..."
    
    # Find the matrix-bot-sdk in the pnpm store (it should be there from the main package build)
    MATRIX_SDK_SRC=$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/node_modules/@vector-im/matrix-bot-sdk" -print -quit 2>/dev/null || true)
    
    if [ -n "$MATRIX_SDK_SRC" ] && [ -d "$MATRIX_SDK_SRC" ]; then
      # Symlink it to the top level so the Matrix plugin can find it
      mkdir -p "$out/lib/openclaw/node_modules/@vector-im"
      if [ ! -e "$out/lib/openclaw/node_modules/@vector-im/matrix-bot-sdk" ]; then
        ln -s "$MATRIX_SDK_SRC" "$out/lib/openclaw/node_modules/@vector-im/matrix-bot-sdk"
        echo "Symlinked Matrix bot SDK from pnpm store"
      fi
    else
      echo "Warning: @vector-im/matrix-bot-sdk not found in pnpm store"
      echo "Matrix plugin will not work until this dependency is available"
    fi
  '';
})

