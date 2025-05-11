{ pkgs, ... }:

{
  users.motd = ''
    ANYONE FOR SOME TEA?!
'';
  users.groups.sam = {};
  users.users = {
    sam = {
      group = "sam";
      shell = pkgs.zsh;
      extraGroups = [ "wireshark" "wheel" "docker" ]; # Enable ‘sudo’ for the user.
      isNormalUser = true;
      initialHashedPassword = "$y$j9T$NPAB.7arQ/BIqdovYTfY6/$506oYwegRg3oO9jTmMTssszCB.VKKTvbvBSOaXuNqB0"; # mkpasswd
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNOSKuCJeOwyOqBF1uYhdT+xBRhfTmfLTFfCjyYbPfTKEN+1lrwq6NIbAlDNaiB2QmyWOkL/q8YZTqL5lsV0f+p5pYOlk4XqJZu75o7qU+UL1NRMKWhP3nkPFaajd3UkcTmS4dghZJbHbHEaQpdforBbsrOleh9p7sskLwABoYFkZDqBZRtgqYvHubsSPTWWzcu97pm8jJnKlj25Qw3WuIH5Arz+0w9ENUNV4Y36Hz+sgP+GhPQCird8O6bXgBPH436P36XdYb/a8SCY96xPMaSaW76tU/XVDImfkH7bGRdwRouO9gzjyzucdO51aK/OLaNitUdWkZVMnO2aQBkBNgvFtshU9fnt6ZLIuovsesACt8mLpNE74lKd4PGHxlz7KLcuBL9ZX3S9yr3TjlhEnb5EAahbhVWZuxVjZTPyOOnHqbFKeCRAmSbNFDrW8xWrzwLmdoSbCqWVmUFOMLEBEDMyOEByKHWpeBz5zFfxTloTNbwdYxgUG3o6xFzV9aYAU="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIKUZsPCBv+914ZE8kLvYuohYRxnymVbf98FJo0xlV1SZAAAABHNzaDo= topaz"
        "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBN+XjleNW8wIwN1W5eNr/lEXz99fg1OH9APvVdwdA0kPJxEOqhMZ4HjIIkgI1BbSKErQ2kiSFnCvHvyT1LUKjR0AAAALdGVybWl1cy5jb20="
      ];
    };
  };
}
