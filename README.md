# nix-config

## Debugging

* Load the flake into the repl
```
nix repl
> :lf .
```

## Misc

### ruby

use [nixpkgs-ruby](https://github.com/bobvanderlinden/nixpkgs-ruby) by executing 

```shell
nix flake init --template github:bobvanderlinden/nixpkgs-ruby#
direnv allow
```

# [nix-direnv](https://github.com/nix-community/nix-direnv)

Either add shell.nix or a default.nix to the project directory:

```nix
# save this as shell.nix
{ pkgs ? import <nixpkgs> {}}:

pkgs.mkShell {
  packages = [ pkgs.hello ];
}
```

Then add the line use nix to your envrc:

```shell
$ echo "use nix" >> .envrc
$ direnv allow
```
