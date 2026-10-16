# yolodo-exec: runs as root through sudo. It re-reads the root-owned system
# policy and runs the rule's exact argv, so a caller can only choose a rule
# name and the flags that rule allows.

policy="@policy@"
die() { echo "yolodo-exec: $*" >&2; exit "${code:-1}"; }

[ "$(id -u)" = 0 ] || die "must run through sudo"
rule="${1:-}"; [ -n "$rule" ] || { code=64; die "usage: yolodo-exec <rule> [--flag]..."; }
shift

# Honour the caller's kill switch even though we run as root.
if [ -n "${SUDO_USER:-}" ]; then
  home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  code=75; [ ! -e "$home/.local/state/yolodo/killed" ] || die "killed"
fi

code=64
r=$(jq -e --arg r "$rule" '.rules[$r]' "$policy") || die "no rule named '$rule'"
[ "$(jq -r '.runAs // "root"' <<<"$r")" = root ] || die "rule '$rule' runs as the user, not through yolodo-exec"

mapfile -t argv < <(jq -r '.command[]' <<<"$r")
for f in "$@"; do
  name="${f#--}"
  [ "$name" != "$f" ] || die "flags look like --name, got '$f'"
  jq -e --arg f "$name" '(.flags // []) | index($f)' <<<"$r" >/dev/null \
    || die "rule '$rule' does not allow --$name"
  argv+=("--$name")
done

exec "${argv[@]}"
