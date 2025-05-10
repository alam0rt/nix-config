

let
  sam = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNOSKuCJeOwyOqBF1uYhdT+xBRhfTmfLTFfCjyYbPfTKEN+1lrwq6NIbAlDNaiB2QmyWOkL/q8YZTqL5lsV0f+p5pYOlk4XqJZu75o7qU+UL1NRMKWhP3nkPFaajd3UkcTmS4dghZJbHbHEaQpdforBbsrOleh9p7sskLwABoYFkZDqBZRtgqYvHubsSPTWWzcu97pm8jJnKlj25Qw3WuIH5Arz+0w9ENUNV4Y36Hz+sgP+GhPQCird8O6bXgBPH436P36XdYb/a8SCY96xPMaSaW76tU/XVDImfkH7bGRdwRouO9gzjyzucdO51aK/OLaNitUdWkZVMnO2aQBkBNgvFtshU9fnt6ZLIuovsesACt8mLpNE74lKd4PGHxlz7KLcuBL9ZX3S9yr3TjlhEnb5EAahbhVWZuxVjZTPyOOnHqbFKeCRAmSbNFDrW8xWrzwLmdoSbCqWVmUFOMLEBEDMyOEByKHWpeBz5zFfxTloTNbwdYxgUG3o6xFzV9aYAU=";
  users = [ sam ];
in
{
  "tailscale-authkey.age".publicKeys = users;
  "tailscale-server.age".publicKeys = users;
  "transmission-credentials.age".publicKeys = users;
  "borg.age".publicKeys = users;
  "maubot-secret-config.age".publicKeys = users;
  "hugging-face-ro-token.age".publicKeys = users;
  "smtp-user.age".publicKeys = users;
  "smtp-pass.age".publicKeys = users;
  "smtp-addr.age".publicKeys = users;
  "matrix-registration-secret.age".publicKeys = users;
}
