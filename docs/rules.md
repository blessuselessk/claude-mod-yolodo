# yolodo rules

A **rule** names one privileged command the agent may run, and says *when* it
may run and *who has to agree*. Rules are declared in Nix (the NixOS,
nix-darwin or home-manager module) and rendered to a JSON policy file the mod
reads at session start. The agent can only ask yolodo to run a rule by name; it
can never pass an arbitrary command to sudo.

## Shape

```nix
services.yolodo.rules.<name> = {
  description = "…";            # shown in the band, the log and /yolodo list
  command     = [ "argv" … ];   # exact argv, run through the yolodo wrapper
  args        = { … };          # optional: named flags the agent may set (allowlisted values only)

  when = {                      # every listed condition must hold (AND)
    after    = [ "<event>" … ]; # events that must have happened, see below
    gates    = [ "<rule>" … ];  # rules that must have succeeded since the last `after` event
    at       = "03:00";         # optional: not before this local time (daily)
    window   = "02:00-06:00";   # optional: only inside this local time window
    quietFor = "30m";           # optional: no user prompt for this long
  };

  countdown = "2m";             # announce, then wait; Cancel stops it, Run now skips it

  auth = "fingerprint";         # fingerprint | passwordless   (see "Auth")

  retry = { attempts = 3; every = "30s"; };
  onFailure = "notify-loud";    # notify | notify-loud | silent

  expires = null;               # optional: "2026-11-01" or "7d"; the rule stops matching after it
};
```

### Events

| Event | Fires when |
| --- | --- |
| `git.push:<repo>@<branch>` | the agent's own Bash call `git push` to that branch exits 0, in this session. Pushes made outside Claude Code never count. |
| `ci.green:<owner>/<repo>@<branch>` | CI for **the commit the agent pushed** concludes `success` (polled with `gh run list`). Other commits on the branch are ignored. |
| `ci.red:…` | same, concluding `failure` (useful for `quietFor`-style rules that should *not* fire) |
| `rule.ok:<rule>` / `rule.fail:<rule>` | another rule finished |
| `prompt` | the user sent a message (resets `quietFor`) |
| `manual` | `/yolodo run <rule>` |

`after` is reset each time the rule runs, so one push lets one switch happen,
not every future one.

## Auth

Each rule picks `auth = "fingerprint"` or `auth = "passwordless"`. Two global
settings decide the default and the limit:

```nix
services.yolodo.auth = {
  default = "fingerprint";       # used by rules that don't say
  allowPasswordless = true;      # false: any passwordless rule fails the Nix build
};
```

The three setups you can have:

| Setup | `default` | `allowPasswordless` |
| --- | --- | --- |
| Fingerprint first (shipped default) | `fingerprint` | `true` |
| Fingerprint only | `fingerprint` | `false` |
| Password-free for everything | `passwordless` | `true` |

* `fingerprint`: the wrapper runs `sudo` inside a pty (`script -qec`) so PAM
  waits on the reader. The band says "touch the scanner". Each retry is a new
  prompt.
* `passwordless`: the Nix module adds a sudoers line for exactly the rule's
  argv through the wrapper, `NOPASSWD`. Only allowed when the rule also has a
  `countdown` (the escape hatch). Meant for unattended triggers (`at`,
  `window`, `quietFor`).

## Escape hatches

* **Cancel** on the countdown band, or `/yolodo cancel`.
* `/yolodo pause` stops every rule for this session; `/yolodo off` stops them
  until turned back on (kept across sessions).
* `yolodo kill` from any terminal: writes a stop file the wrapper checks
  before every run, so it works even when Claude Code is not responding.
* Removing the rule from Nix and rebuilding removes its sudoers line too;
  rolling back a generation restores the previous rule set.

## Log

Every decision (armed, countdown started, cancelled, ran, exit code, retries)
is appended to `~/.local/state/yolodo/log.jsonl` and shown by `/yolodo log`.

## The first rule: rebuilding hornicorn

Taken from `blessuselessk/lul` (`CLAUDE.md`, `README.md`,
`modules/hosts/hornicorn.nix`):

```nix
services.yolodo.rules = {
  # No sudo; listed so `rebuild` can gate on it and it shows in the log.
  # Default check: boot the VM headless and pass once greetd is up.
  # A risky change opts into the interactive check instead (see below).
  rebuild-vm = {
    description = "Boot the CI-built hornicorn closure in a VM";
    command = [ "yolodo-vm-check" "--flake" "github:blessuselessk/lul#hornicorn" "--until" "greetd.service" ];
    privileged = false;
    when.after = [ "ci.green:blessuselessk/lul@master" ];
    manualCheck = {
      when = "commit-trailer:Yolodo-Check=manual";   # or the agent asks for it
      command = [ "hornicorn-rebuild-vm" ];         # opens the VM window
      passWith = "button";                           # you press "Looks good" or "Reject"
    };
  };

  rebuild = {
    description = "Switch hornicorn to the CI-built closure";
    command = [ "hornicorn-rebuild" ];
    args.no-push = [ true false ];
    when = {
      after = [ "ci.green:blessuselessk/lul@master" ];
      gates = [ "rebuild-vm" ];
    };
    countdown = "30s";
    auth = "fingerprint";
    retry = { attempts = 3; every = "30s"; };
    onFailure = "notify-loud";
  };
};
```

## Decided

* **VM check:** headless boot to the login screen by default. A change is
  checked by hand instead when its commit carries `Yolodo-Check: manual`, or
  when the agent marks it risky. Then the VM window opens and the rule waits
  for **Looks good** or **Reject**.
* **What arms a rebuild:** only a push the agent itself made in that Claude
  Code session, and only that commit's CI result.
