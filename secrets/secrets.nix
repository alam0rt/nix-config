let
  sam = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNOSKuCJeOwyOqBF1uYhdT+xBRhfTmfLTFfCjyYbPfTKEN+1lrwq6NIbAlDNaiB2QmyWOkL/q8YZTqL5lsV0f+p5pYOlk4XqJZu75o7qU+UL1NRMKWhP3nkPFaajd3UkcTmS4dghZJbHbHEaQpdforBbsrOleh9p7sskLwABoYFkZDqBZRtgqYvHubsSPTWWzcu97pm8jJnKlj25Qw3WuIH5Arz+0w9ENUNV4Y36Hz+sgP+GhPQCird8O6bXgBPH436P36XdYb/a8SCY96xPMaSaW76tU/XVDImfkH7bGRdwRouO9gzjyzucdO51aK/OLaNitUdWkZVMnO2aQBkBNgvFtshU9fnt6ZLIuovsesACt8mLpNE74lKd4PGHxlz7KLcuBL9ZX3S9yr3TjlhEnb5EAahbhVWZuxVjZTPyOOnHqbFKeCRAmSbNFDrW8xWrzwLmdoSbCqWVmUFOMLEBEDMyOEByKHWpeBz5zFfxTloTNbwdYxgUG3o6xFzV9aYAU=";
  yubikey-22916238 = "age1fido2-hmac1qqpdn0xrflfkf5fytgndususgmqqwu047f03fey6ptn2g0dlm5ynvlqqujpa2auu7yx5hkw7t5dtx7q0xnxtnsk76d6t3m5fr4ccgfx6v5qachlvravk96lf0sdwjhwshztlj2vh888lzkpfr5nez2j6n6f92m3necp834lwv7yahv86qemuvgev5rut36g6muwl7fvk2ecdqe4wjcca794l";
  yubikey-15498888 = "age1fido2-hmac1qqpxuckgas4x9yurjudd3rlxnn7cuyrtf5y5l7wj75ru0xsffdcgv3gq6ytcffzzvdsm8cyj6vpfgpwy5fhlfu8kqyyy9v6ukcms9cxxf59gnark9z240x3y9ln7vh7vcsyj4n766ccj9qvfmnsmspcje5fr3qnqxvjs98q0tk0pj3rr9gtn7734v3qcx54gycut9vqcdqfhszhqju37kwkk";
  hwkeys = [yubikey-22916238 yubikey-15498888];
  users = [sam] ++ hwkeys;
in {
  "tailscale-authkey.age".publicKeys = users;
  "tailscale-server.age".publicKeys = users;
  "transmission-credentials.age".publicKeys = users;
  "borg.age".publicKeys = users;
  "maubot-secret-config.age".publicKeys = users;
  "hugging-face-ro-token.age".publicKeys = users;
  "smtp-user.age".publicKeys = users;
  "smtp-pass.age".publicKeys = users;
  "smtp-addr.age".publicKeys = users;
}
