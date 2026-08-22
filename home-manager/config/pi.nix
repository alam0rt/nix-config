# pi coding agent: package + personal extensions.
{inputs, ...}: {
  imports = [inputs.omp.homeManagerModules.default];

  programs.omp = {
    enable = true;
  };
}
