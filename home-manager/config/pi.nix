# pi coding agent: package + personal extensions.
{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.omp.homeManagerModules.default];

  programs.omp = {
    enable = true;
  };

  # Switchyard LLM routing proxy. Create routes.toml (see the upstream
  # getting-started guide), then run:
  #   switchyard-server --config routes.toml --host 127.0.0.1 --port 4000
  # OMP talks to it through a `switchyard` provider entry in
  # ~/.omp/agent/models.yml, configured per-machine (on darwin that file is
  # managed declaratively in private-flake home-manager/darwin.nix).
  home.packages = [pkgs.switchyard];
}
