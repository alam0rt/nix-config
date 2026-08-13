{
  lib,
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
}:
# OIDC SSO plugin for Jellyfin, built from our fork.
#
# The fork carries security fixes not yet upstream (PRs Ezeqielle/jellyfin-plugin-oidc#25 and
# #26): upstream never cryptographically validated the ID token, and keyed Jellyfin accounts on
# the mutable `preferred_username` claim rather than `sub`. Track the PRs and move back to
# upstream once they land.
buildDotnetModule (finalAttrs: {
  pname = "jellyfin-plugin-oidc";
  # Upstream plugin version (meta.json / build.yaml) plus a fork suffix, so it is obvious in the
  # Jellyfin dashboard that this is not a catalog build.
  version = "1.0.8.0-fork1";

  src = fetchFromGitHub {
    owner = "alam0rt";
    repo = "jellyfin-plugin-oidc";
    rev = "03a493d2ca78e22f117302aea320c44249256260";
    hash = "sha256-wWNpohBKkMgYUzzPMQ/eu8FIsXHs8VrJ0bd1RgjrL+k=";
  };

  projectFile = "Jellyfin.Plugin.OIDC/Jellyfin.Plugin.OIDC.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_9_0;
  # The plugin targets Microsoft.AspNetCore.App; the Jellyfin host supplies it at runtime, but
  # the build needs it present.
  dotnet-runtime = dotnetCorePackages.aspnetcore_9_0;

  # A plugin assembly, not a program — nothing to wrap.
  executables = [];

  # Jellyfin discovers plugins by scanning <dataDir>/plugins/*/ for meta.json, so the payload has
  # to be a flat directory of assemblies. buildDotnetModule's default layout under lib/$pname is
  # already flat; this just drops the build leftovers Jellyfin would otherwise try to inspect.
  postFixup = ''
    rm -f "$out/lib/${finalAttrs.pname}"/*.pdb
  '';

  meta = {
    description = "OpenID Connect SSO plugin for Jellyfin with role-based library access control";
    homepage = "https://github.com/alam0rt/jellyfin-plugin-oidc";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    maintainers = [];
  };
})
