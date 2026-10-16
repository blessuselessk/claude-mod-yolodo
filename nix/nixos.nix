self:
{ config, lib, pkgs, ... }:

let cfg = config.services.yolodo;
in
{
  imports = [ ./common.nix ];

  config = lib.mkMerge [
    { services.yolodo.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.yolodo; }
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
      environment.etc."yolodo/policy.json".source = cfg.policyFile;
      security.sudo.extraConfig = lib.mkIf (cfg.sudoersLines != [ ]) (lib.mkAfter ''
        # yolodo: passwordless rules
        ${lib.concatStringsSep "\n" cfg.sudoersLines}
      '');
    })
  ];
}
