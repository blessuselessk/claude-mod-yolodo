# yolodo

You Only Live Once... Do. A Claude Code mod plus Nix flake that lets an agent
run allowlisted sudo commands under conditions you declare (countdowns, set
times, events, silence), with fingerprint or password-free auth and escape
hatches.

Status: design. See [docs/rules.md](docs/rules.md).

## Using it from a NixOS flake

```nix
inputs.yolodo.url = "github:blessuselessk/claude-mod-yolodo";

# in a NixOS module
imports = [ inputs.yolodo.nixosModules.yolodo ];
services.yolodo = {
  enable = true;
  user = "lessuseless";
  rules.rebuild = {
    command = [ "hornicorn-rebuild" ];
    runAs = "user";          # hornicorn-rebuild does its own sudo
    flags = [ "no-push" ];
  };
};
```

Then `yolodo list`, `yolodo run rebuild [--no-push]`, `yolodo kill`,
`yolodo unkill`, `yolodo log`. nix-darwin uses `darwinModules.yolodo`.

The Claude Code mod that decides *when* to call `yolodo run` comes in step 3.
Today the wrapper, the policy file, the sudoers lines and the kill switch work
on their own.

## Tests

`nix flake check` boots a NixOS VM and checks: a passwordless rule runs as
root, only allowed flags pass, unknown rules are refused, a fingerprint rule
won't run without auth, sudo allows only the exact rule argv, the kill switch
stops both sides, and runs are logged.
