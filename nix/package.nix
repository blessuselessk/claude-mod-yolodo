{ lib, stdenvNoCC, writeShellApplication, jq, util-linux, coreutils, glibc }:

let
  policy = "/etc/yolodo/policy.json";

  yolodo-exec = writeShellApplication {
    name = "yolodo-exec";
    runtimeInputs = [ jq coreutils ] ++ lib.optional stdenvNoCC.hostPlatform.isLinux glibc.getent;
    text = builtins.replaceStrings [ "@policy@" ] [ policy ] (builtins.readFile ../src/yolodo-exec.sh);
  };

  yolodo = writeShellApplication {
    name = "yolodo";
    runtimeInputs = [ jq coreutils ] ++ lib.optional stdenvNoCC.hostPlatform.isLinux util-linux;
    text = builtins.replaceStrings
      [ "@policy@" "@exec@" ]
      [ policy "${yolodo-exec}/bin/yolodo-exec" ]
      (builtins.readFile ../src/yolodo.sh);
  };
in
stdenvNoCC.mkDerivation {
  pname = "yolodo";
  version = "0.1.0";
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/bin
    ln -s ${yolodo}/bin/yolodo $out/bin/yolodo
    ln -s ${yolodo-exec}/bin/yolodo-exec $out/bin/yolodo-exec
  '';
  passthru = {
    inherit policy;
    # The exact store path sudoers allows. Kept separate from $out/bin so a
    # sudoers line never names a symlink.
    execPath = "${yolodo-exec}/bin/yolodo-exec";
  };
  meta = {
    description = "Run allowlisted sudo rules for Claude Code under declared conditions";
    mainProgram = "yolodo";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
