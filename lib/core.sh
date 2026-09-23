# core.sh — shared helpers: messages, cleanup, prompts, config, path safety, Delphi git access.
# Sourced by bin/delphi. Bash 3.2 compatible: no associative arrays, no mapfile.
# Critical commands use explicit `|| die` rather than relying on `set -e`, because errexit is
# suspended inside functions called from conditionals.

CONTEXT_DIR="$DELPHI_ROOT/context"

die()  { printf 'delphi: %s\n' "$*" >&2; exit 1; }
warn() { printf 'delphi: warning: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*" >&2; }

# ---- cleanup: deferred commands run LIFO on exit ----
_DEFERRED=""
defer() { _DEFERRED="$1
$_DEFERRED"; }
_run_deferred() {
  local IFS='
' c
  for c in $_DEFERRED; do eval "$c" >/dev/null 2>&1 || true; done
}
trap _run_deferred EXIT

# Functions that register cleanup must not run inside $(...) (a subshell would lose the
# registration), so they return their result in REPLY instead of printing it.

# make_tmp: new temp dir in REPLY, removed on exit.
make_tmp() {
  REPLY=$(mktemp -d "${TMPDIR:-/tmp}/delphi.XXXXXX") || die "mktemp failed"
  defer "rm -rf $(printf %q "$REPLY")"
}

# ---- prompts ----
# stdin + stderr (prompts go to stderr), so prompting works inside $(...).
is_tty() { [ -t 0 ] && [ -t 2 ]; }

# confirm <question>: yes if DELPHI_YES=1; fails fast when non-interactive.
confirm() {
  [ "${DELPHI_YES:-}" = 1 ] && return 0
  is_tty || die "non-interactive session: re-run with --yes (or DELPHI_YES=1)"
  local a
  read -r -p "$1 [y/N] " a
  case $a in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

# ask <question> [default]: prints the answer.
ask() {
  is_tty || die "non-interactive session: cannot ask '$1'"
  local a
  read -r -p "$1${2:+ [$2]} " a
  printf '%s\n' "${a:-${2:-}}"
}

# ---- config ----
# conf_get <key> <default>: reads delphi.conf (key=value lines; never sourced).
conf_get() {
  local v=""
  [ -f "$DELPHI_ROOT/delphi.conf" ] &&
    v=$(awk -F= -v k="$1" '$0 !~ /^#/ && $1==k { sub(/^[^=]*=/, ""); print; exit }' "$DELPHI_ROOT/delphi.conf")
  printf '%s\n' "${v:-$2}"
}

workspace_root() {
  local r=${DELPHI_WORKSPACE_ROOT:-$(conf_get workspace_root ../Delphi-workspaces)}
  case $r in /*) ;; *) r="$DELPHI_ROOT/$r" ;; esac
  if [ -d "$r" ]; then r=$(cd -P "$r" && pwd)
  elif [ -d "${r%/*}" ]; then r="$(cd -P "${r%/*}" && pwd)/${r##*/}"; fi
  printf '%s\n' "$r"
}

# ---- path safety ----
# path_ok <rel>: relative, no '..' or '.' components, not empty.
path_ok() {
  case $1 in ""|/*) return 1 ;; esac
  case "/$1/" in */../*|*/./*|*//*) return 1 ;; esac
  return 0
}

# safe_path <root> <rel>: prints <root>/<rel> after proving it stays inside <root>
# (lexically and through symlinks). Dies otherwise.
safe_path() {
  local root=$1 rel=$2 rroot probe real
  path_ok "$rel" || die "unsafe path: '$rel'"
  rroot=$(cd -P "$root" 2>/dev/null && pwd) || die "missing directory: $root"
  probe="$rroot/$rel"
  [ -L "$probe" ] && die "unsafe path (symlink): '$rel'"
  while [ ! -e "$probe" ]; do probe=$(dirname "$probe"); done
  [ -d "$probe" ] || probe=$(dirname "$probe")
  real=$(cd -P "$probe" && pwd)
  case "$real/" in "$rroot"/*) ;; *) die "unsafe path (escapes $root): '$rel'" ;; esac
  printf '%s\n' "$rroot/$rel"
}

# ---- Delphi repo access ----
dgit() { git -c core.quotePath=false -C "$DELPHI_ROOT" "$@"; }

delphi_fetch() {
  [ "${DELPHI_OFFLINE:-}" = 1 ] && return 0
  dgit fetch --prune --quiet origin 2>/dev/null || warn "git fetch failed; using local refs"
}

# delphi_commit <branch>: full sha of origin/<branch>, or dies.
delphi_commit() {
  dgit rev-parse --verify --quiet "origin/$1^{commit}" || die "no such Delphi branch: origin/$1"
}

# delphi_worktree_at <commit>: detached temp worktree of Delphi; path in REPLY.
delphi_worktree_at() {
  local d
  make_tmp; d="$REPLY/src"
  dgit worktree add --quiet --detach "$d" "$1" >/dev/null 2>&1 || die "cannot check out Delphi at $1"
  defer "git -C $(printf %q "$DELPHI_ROOT") worktree remove --force $(printf %q "$d")"
  REPLY=$d
}

# find_layout <tree-root> <name>: prints the layout dir relative to context/.
find_layout() {
  local root=$1 name=$2 hits n
  case $name in *[!a-z0-9-]*|"") die "invalid layout name: '$name'" ;; esac
  hits=$(cd "$root/context" && find . -path "*/layouts/$name/manifest.yml" -type f | sed 's#^\./##; s#/manifest.yml$##')
  n=$(printf '%s' "$hits" | awk 'END { print NR }')
  [ "$n" -eq 1 ] || { [ "$n" -eq 0 ] && die "layout not found: $name"; die "layout name not unique: $name"; }
  printf '%s\n' "$hits"
}

# load_harness <name>: sources lib/harness/<name>.sh and checks the contract.
load_harness() {
  case $1 in *[!a-z0-9-]*|"") die "invalid harness name: '$1'" ;; esac
  [ -f "$DELPHI_ROOT/lib/harness/$1.sh" ] || die "unknown harness: $1"
  . "$DELPHI_ROOT/lib/harness/$1.sh"
  : "${HARNESS_INSTRUCTIONS:?adapter $1: HARNESS_INSTRUCTIONS unset}"
  : "${HARNESS_SKILLS_DIR:?adapter $1: HARNESS_SKILLS_DIR unset}"
  : "${HARNESS_MCP_FILE:?adapter $1: HARNESS_MCP_FILE unset}"
  : "${HARNESS_SETTINGS_FILE:?adapter $1: HARNESS_SETTINGS_FILE unset}"
}

# in_list <needle> <newline-separated list>
in_list() { printf '%s\n' "$2" | grep -Fxq -- "$1"; }

# ---- moves (moves.tsv is append-only; rows apply in order, each once) ----
_MV_AWK='BEGIN { while ((getline l < M) > 0) if (l !~ /^#/ && split(l, f, "\t") >= 2) { n++; O[n] = f[1]; N[n] = f[2] } }
  function mv(p,   i) {
    for (i = 1; i <= n; i++)
      if (p == O[i]) p = N[i]; else if (index(p, O[i] "/") == 1) p = N[i] substr(p, length(O[i]) + 1)
    return p }'

# moves_since <old-commit> <new-commit>: moves.tsv rows added between two Delphi commits; file in REPLY.
moves_since() {
  local n
  n=$(dgit show "$1:moves.tsv" 2>/dev/null | awk 'END { print NR }') || true
  make_tmp; REPLY="$REPLY/moves"
  dgit show "$2:moves.tsv" 2>/dev/null | awk -v n="${n:-0}" 'NR > n' > "$REPLY" || true
}

# move_path <rows> <path>: prints the path with the move rows applied.
move_path() { printf '%s\n' "$2" | awk -v M="$1" "$_MV_AWK"' { print mv($0) }'; }

# rewrite_moves <rows> <file>: applies move rows to `  - item` lines and `settings:` values in
# place (trailing comments on rewritten lines are dropped). Returns 0 if it changed anything.
rewrite_moves() {
  awk -v M="$1" "$_MV_AWK"'
    { pre = $0 ~ /^  - / ? "  - " : $0 ~ /^settings: / ? "settings: " : ""
      if (pre != "") { v = substr($0, length(pre) + 1); sub(/ #.*/, "", v); sub(/ +$/, "", v)
        if (mv(v) != v) { $0 = pre mv(v); ch = 1 } }
      print }
    END { exit !ch }' "$2" > "$2.tmp" && mv "$2.tmp" "$2" && return 0
  rm -f "$2.tmp"; return 1
}

# parse_args "<allowed flags>" <args…>: flags into OPT_* (valued: --as --ref --from --model
# --effort; switches: --yes --shell --dry-run --offline); positionals, shell-quoted, into ARGS.
# Callers: parse_args "--yes …" "$@"; eval "set -- $ARGS"
parse_args() {
  local ok=" $1 "
  shift
  ARGS="" OPT_AS="" OPT_REF="" OPT_FROM="" OPT_MODEL="" OPT_EFFORT="" OPT_SHELL="" OPT_DRY=""
  while [ $# -gt 0 ]; do
    case $1 in -*) case $ok in *" $1 "*) ;; *) die "unknown flag for this command: $1 (allowed:${ok% })" ;; esac ;; esac
    case $1 in
      --as|--ref|--from|--model|--effort)
        [ $# -ge 2 ] || die "$1 needs a value"
        case $1 in
          --as) OPT_AS=$2 ;; --ref) OPT_REF=$2 ;; --from) OPT_FROM=$2 ;;
          --model) OPT_MODEL=$2 ;; --effort) OPT_EFFORT=$2 ;;
        esac
        shift ;;
      --yes) DELPHI_YES=1 ;;
      --shell) OPT_SHELL=1 ;;
      --dry-run) OPT_DRY=1 ;;
      --offline) DELPHI_OFFLINE=1 ;;
      *) ARGS="$ARGS $(printf %q "$1")" ;;
    esac
    shift
  done
}
