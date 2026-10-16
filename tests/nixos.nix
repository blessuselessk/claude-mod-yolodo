{ self, pkgs }:

pkgs.testers.runNixOSTest {
  name = "yolodo";
  nodes.machine = { pkgs, ... }: {
    imports = [ self.nixosModules.yolodo ];
    users.users.alice = { isNormalUser = true; password = "x"; };
    services.yolodo = {
      enable = true;
      user = "alice";
      rules = {
        whoami = {
          command = [ "${pkgs.coreutils}/bin/id" "-u" ];
          auth = "passwordless";
          countdown = "5s";
        };
        greet = {
          command = [ "${pkgs.coreutils}/bin/echo" "hello" ];
          flags = [ "loud" ];
          auth = "passwordless";
          countdown = "5s";
        };
        guarded = {
          command = [ "${pkgs.coreutils}/bin/id" "-u" ];
          # default auth: fingerprint, so sudo asks and nothing answers
        };
      };
    };
  };

  testScript = ''
    def alice(cmd):
        return f"su - alice -c '{cmd}'"

    machine.wait_for_unit("multi-user.target")

    with subtest("passwordless rule runs as root"):
        out = machine.succeed(alice("yolodo run whoami"))
        assert out.strip().endswith("0"), out

    with subtest("allowed flag passes through, unknown flag is refused"):
        out = machine.succeed(alice("yolodo run greet --loud"))
        assert "hello --loud" in out, out
        machine.fail(alice("yolodo run greet --quiet"))

    with subtest("unknown rule is refused"):
        machine.fail(alice("yolodo run nope"))

    with subtest("fingerprint rule does not run without auth"):
        machine.fail(alice("timeout 20 yolodo run guarded </dev/null"))

    with subtest("sudo allows only the exact rule argv"):
        exec_path = machine.succeed("grep -o '/nix/store/[^ ]*/bin/yolodo-exec' /etc/sudoers | head -1").strip()
        machine.fail(alice(f"sudo -n {exec_path} guarded"))
        machine.fail(alice(f"sudo -n {exec_path} whoami --extra"))
        machine.fail(alice("sudo -n id -u"))

    with subtest("kill switch stops runs, including the root side"):
        machine.succeed(alice("yolodo kill"))
        machine.fail(alice("yolodo run whoami"))
        machine.fail(alice(f"sudo -n {exec_path} whoami"))
        machine.succeed(alice("yolodo unkill"))
        machine.succeed(alice("yolodo run whoami"))

    with subtest("every run is logged"):
        machine.succeed(alice("grep -q event.:.exit ~/.local/state/yolodo/log.jsonl"))
  '';
}
