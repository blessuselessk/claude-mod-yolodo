# yolodo: run an allowlisted rule by name. The agent never passes a command,
# only a rule name and flags the rule allows.
#
# @exec@ and @policy@ are substituted at build time. The two *_OVERRIDE
# variables exist for tests; yolodo-exec ignores them and always reads the
# system policy.

policy="${YOLODO_POLICY_OVERRIDE:-@policy@}"
exec_bin="@exec@"
sudo_bin="${YOLODO_SUDO_OVERRIDE:-sudo}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/yolodo"
mkdir -p "$state"

log() { # event rule [key value]...
  local event=$1 rule=$2; shift 2
  jq -cn --arg t "$(date -Is)" --arg e "$event" --arg r "$rule" \
    '$ARGS.positional as $a | {t:$t, event:$e, rule:$r} + ([range(0; $a | length; 2) | {($a[.]): $a[. + 1]}] | add // {})' \
    --args "$@" >>"$state/log.jsonl"
}

die() { echo "yolodo: $*" >&2; exit "${code:-1}"; }

usage() {
  cat <<USAGE
usage: yolodo list
       yolodo run <rule> [--<flag>]...
       yolodo kill | unkill | status
       yolodo log [n]
USAGE
}

[ -r "$policy" ] || die "no policy at $policy"

case "${1:-}" in
  list)
    jq -r '.rules | to_entries[] | "\(.key)\t\(.value.auth // "-")\t\(.value.description // "")"' "$policy"
    ;;
  kill)
    date -Is >"$state/killed"; log kill -
    echo "yolodo: every rule is stopped until 'yolodo unkill'"
    ;;
  unkill)
    rm -f "$state/killed"; log unkill -
    echo "yolodo: rules may run again"
    ;;
  status)
    if [ -e "$state/killed" ]; then echo "killed since $(cat "$state/killed")"; else echo "armed"; fi
    ;;
  log)
    tail -n "${2:-20}" "$state/log.jsonl" 2>/dev/null || true
    ;;
  run)
    rule="${2:-}"; [ -n "$rule" ] || { usage >&2; exit 64; }
    shift 2
    code=75; [ ! -e "$state/killed" ] || die "killed (yolodo unkill to re-arm)"
    code=64
    r=$(jq -e --arg r "$rule" '.rules[$r]' "$policy") || die "no rule named '$rule'"

    flags=()
    for f in "$@"; do
      name="${f#--}"
      [ "$name" != "$f" ] || die "flags look like --name, got '$f'"
      jq -e --arg f "$name" '(.flags // []) | index($f)' <<<"$r" >/dev/null \
        || die "rule '$rule' does not allow --$name"
      flags+=("--$name")
    done

    run_as=$(jq -r '.runAs // "root"' <<<"$r")
    auth=$(jq -r --slurpfile p "$policy" '.auth // $p[0].auth.default' <<<"$r")

    if [ "$run_as" = user ]; then
      # The command does its own sudo (e.g. hornicorn-rebuild). Give it a pty
      # so PAM can wait on the fingerprint reader.
      mapfile -t argv < <(jq -r '.command[]' <<<"$r")
      cmd=$(printf '%q ' "${argv[@]}" "${flags[@]}")
    elif [ "$auth" = passwordless ]; then
      cmd=$(printf '%q ' "$sudo_bin" -n "$exec_bin" "$rule" "${flags[@]}")
    else
      cmd=$(printf '%q ' "$sudo_bin" "$exec_bin" "$rule" "${flags[@]}")
    fi

    log start "$rule" auth "$auth" runAs "$run_as"
    set +e
    if [ "$(uname)" = Darwin ]; then
      script -q /dev/null sh -c "$cmd"
    else
      script -qec "$cmd" /dev/null
    fi
    status=$?
    set -e
    log exit "$rule" status "$status"
    exit "$status"
    ;;
  -h|--help|"") usage ;;
  *) usage >&2; exit 64 ;;
esac
