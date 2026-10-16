{
  description = "yolodo: allowlisted, conditional sudo for Claude Code";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs: rec {
        yolodo = pkgs.callPackage ./nix/package.nix { };
        default = yolodo;
      });

      apps = forAll (pkgs: rec {
        yolodo = { type = "app"; program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.yolodo}/bin/yolodo"; };
        default = yolodo;
      });

      nixosModules = rec { yolodo = import ./nix/nixos.nix self; default = yolodo; };
      darwinModules = rec { yolodo = import ./nix/darwin.nix self; default = yolodo; };

      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: {
        nixos = import ./tests/nixos.nix { inherit self; pkgs = nixpkgs.legacyPackages.${system}; };
      });
    };
}
