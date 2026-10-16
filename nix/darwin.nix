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
      # Fingerprint rules on macOS use Touch ID: security.pam.services.sudo_local.touchIdAuth = true;
      environment.etc."sudoers.d/yolodo" = lib.mkIf (cfg.sudoersLines != [ ]) {
        text = lib.concatStringsSep "\n" cfg.sudoersLines + "\n";
      };
    })
  ];
}
