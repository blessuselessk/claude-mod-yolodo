# Options and policy rendering shared by the NixOS and nix-darwin modules.
# `sudoersLines` is applied by each platform module in its own way.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.services.yolodo;
  json = (pkgs.formats.json { }).type;

  ruleModule = { name, ... }: {
    # Anything not declared here (when, countdown, retry, onFailure, expires,
    # manualCheck, …) passes through to the policy for the mod to read.
    freeformType = json;
    options = {
      description = mkOption { type = types.str; default = name; };
      command = mkOption {
        type = types.nonEmptyListOf types.str;
        description = "Exact argv. The agent can only add flags listed in `flags`.";
      };
      flags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "no-push" ];
        description = "Boolean --flags the agent may append.";
      };
      runAs = mkOption {
        type = types.enum [ "root" "user" ];
        default = "root";
        description = ''
          root: yolodo runs the command through sudo and yolodo-exec.
          user: the command does its own sudo (like hornicorn-rebuild); yolodo
          only gives it a pty so the fingerprint prompt can wait.
        '';
      };
      auth = mkOption {
        type = types.nullOr (types.enum [ "fingerprint" "passwordless" ]);
        default = null;
        description = "null uses services.yolodo.auth.default.";
      };
    };
  };

  effectiveAuth = r: if r.auth == null then cfg.auth.default else r.auth;
  passwordless = lib.filterAttrs (_: r: r.runAs == "root" && effectiveAuth r == "passwordless") cfg.rules;

  # Every flag combination is spelled out, because sudoers matches exact argv.
  flagCombos = flags:
    lib.foldr (f: acc: acc ++ map (c: [ "--${f}" ] ++ c) acc) [ [ ] ] flags;
  # Space, comma, colon, equals and backslash are special in sudoers.
  esc = lib.replaceStrings [ "\\" " " "," ":" "=" ] [ "\\\\" "\\ " "\\," "\\:" "\\=" ];
  sudoersFor = name: r: map
    (c: "${cfg.user} ALL=(root) NOPASSWD: ${cfg.package.execPath} ${lib.concatMapStringsSep " " esc ([ name ] ++ c)}")
    (flagCombos r.flags);
in
{
  options.services.yolodo = {
    enable = mkEnableOption "yolodo";
    package = mkOption { type = types.package; };
    user = mkOption {
      type = types.str;
      description = "The one user whose agent may run passwordless rules.";
    };
    auth = {
      default = mkOption {
        type = types.enum [ "fingerprint" "passwordless" ];
        default = "fingerprint";
      };
      allowPasswordless = mkOption {
        type = types.bool;
        default = true;
        description = "false makes any passwordless rule fail the build.";
      };
    };
    rules = mkOption {
      type = types.attrsOf (types.submodule ruleModule);
      default = { };
    };

    # Internal: read by the platform modules.
    policyFile = mkOption { type = types.path; internal = true; readOnly = true; };
    sudoersLines = mkOption { type = types.listOf types.str; internal = true; readOnly = true; };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (name: r: {
        assertion = effectiveAuth r != "passwordless" || cfg.auth.allowPasswordless;
        message = "yolodo rule '${name}' is passwordless but services.yolodo.auth.allowPasswordless is false.";
      }) cfg.rules
      ++ lib.mapAttrsToList (name: r: {
        assertion = !(r.runAs == "user" && effectiveAuth r == "passwordless");
        message = "yolodo rule '${name}' runs as the user, which does its own sudo, so it can't be passwordless. Use runAs = \"root\".";
      }) cfg.rules
      ++ lib.mapAttrsToList (name: r: {
        assertion = (r.countdown or null) != null;
        message = "yolodo rule '${name}' is passwordless, so it needs a countdown (the window to Cancel it).";
      }) passwordless;

    services.yolodo.policyFile = pkgs.writeText "yolodo-policy.json" (builtins.toJSON {
      version = 1;
      inherit (cfg) auth;
      rules = lib.mapAttrs (_: r: r // { auth = effectiveAuth r; }) cfg.rules;
    });
    services.yolodo.sudoersLines = lib.concatLists (lib.mapAttrsToList sudoersFor passwordless);
  };
}
