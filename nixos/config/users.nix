{ config, pkgs, ... }:

{
  users.groups.sam = {};
  users.users = {
    sam = {
      group = "sam";
      extraGroups = [ "wheel" "docker" ]; # Enable ‘sudo’ for the user.
      shell = "/bin/zsh";
      isNormalUser = true;
      initialHashedPassword = "$y$j9T$NPAB.7arQ/BIqdovYTfY6/$506oYwegRg3oO9jTmMTssszCB.VKKTvbvBSOaXuNqB0"; # mkpasswd
      packages = with pkgs; [
        docker
        super-slicer-latest
      ];
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNOSKuCJeOwyOqBF1uYhdT+xBRhfTmfLTFfCjyYbPfTKEN+1lrwq6NIbAlDNaiB2QmyWOkL/q8YZTqL5lsV0f+p5pYOlk4XqJZu75o7qU+UL1NRMKWhP3nkPFaajd3UkcTmS4dghZJbHbHEaQpdforBbsrOleh9p7sskLwABoYFkZDqBZRtgqYvHubsSPTWWzcu97pm8jJnKlj25Qw3WuIH5Arz+0w9ENUNV4Y36Hz+sgP+GhPQCird8O6bXgBPH436P36XdYb/a8SCY96xPMaSaW76tU/XVDImfkH7bGRdwRouO9gzjyzucdO51aK/OLaNitUdWkZVMnO2aQBkBNgvFtshU9fnt6ZLIuovsesACt8mLpNE74lKd4PGHxlz7KLcuBL9ZX3S9yr3TjlhEnb5EAahbhVWZuxVjZTPyOOnHqbFKeCRAmSbNFDrW8xWrzwLmdoSbCqWVmUFOMLEBEDMyOEByKHWpeBz5zFfxTloTNbwdYxgUG3o6xFzV9aYAU="
      ];
    };
  };
}
