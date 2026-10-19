#!/usr/bin/env bash
# .delphi/setup.sh: run in a checkout of ws/<name> (the workspace root; .delphi/ comes from Delphi's
# main, which sync keeps on every ws/* branch, so edit it only there; on main this does nothing). For each repo listed under
# `repos:` in workspace.yml, clones it at repos/<name> (unless present). Separately, fetches it into a
# bare store at worktrees/<name>/.bare (unless present) and checks out its default branch as the first
# worktree, worktrees/<name>/<default-branch> (re-created if missing); .delphi/new-worktree.sh makes the
# others from that store, so worktrees never touch the clone. For each repo under
# `references-git:` (read-only dependency sources, `<name>: <git-url> [<ref>]`), checks out a shallow,
# detached copy of <ref> (default: origin's default branch) at references/<name>, refreshed on every
# run, with pushes disabled. Each entry under `workspaces:` (`- <name>`, a workspace's dotted name
# from .delphi/names.sh, or `- main`) gets a full clone of this clone's origin (Delphi) at workspaces/<name>,
# on ws/<name> (or main) tracking origin; every run switches it back to that branch if it was switched
# away (its own .delphi/switch.sh), pulls it, then runs its own setup.sh, so its repos and references are
# there too. A workspace that is itself one of those (<workspace>/workspaces/<name>) skips its own
# workspaces:, so setups never chain. By convention they're read from here, not edited. Adds the
# folders park.sh parks and macOS's .DS_Store to this clone's .git/info/exclude, and writes its post-checkout hook, which runs .delphi/park.sh (on
# every branch) as just checked out in the worktree that checked out (unless another hook is there), so switching
# to another workspace or main parks those folders. First
# it runs the .delphi/migrations/<version>-*.sh this workspace hasn't (oldest first; the last one done
# is `git config delphi.<name>.version`, else the record under its old name, its folder's path without
# workspaces/, from origin/main; 0.0.0 if neither), stopping at one that fails, and warns if
# .delphi/ isn't exactly the version it says (.delphi/version.sh). Last, it brings this machine's Delphi plugins in
# step with the workspace (.delphi/plugins.sh: installs what it enables, uninstalls local ones it doesn't and what the marketplace dropped). Safe to re-run. Keep it bash 3.2
# (macOS) and Git Bash safe: no bash-4 features, POSIX awk only.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f workspace.yml ] || { echo "setup: no workspace.yml here (on main?); nothing to set up" >&2 && exit 0; }
self=$(awk '/^name:/ { print $2; exit }' workspace.yml)
inside= # set when this is another workspace's workspaces/<name>: its own workspaces: are skipped
[ "$(basename "$(dirname "$PWD")")" != workspaces ] || [ ! -f ../../workspace.yml ] || [ ! -d ../../.delphi ] || inside=${PWD%/*/*}
case "$self" in "" | [-.]* | *. | *..* | *[!a-z0-9.-]*) echo "setup: workspace.yml needs a valid name:" >&2 && exit 1 ;; esac

older() { # <a> <b>: a is a lower MAJOR.MINOR.PATCH than b
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$1" ]
}
here=$(bash .delphi/version.sh) released=$(grep -v '^#' .delphi/versions | grep . | tail -n 1 | cut -d' ' -f1,2 || true)
[ "$here" = "$released" ] ||
  echo "setup: .delphi/ is not Delphi ${released%% *} as released (edited here? change it only through main)" >&2
old=$(bash .delphi/names.sh refs/remotes/origin/main 2>/dev/null | awk -v n="$self" '$1 == n { sub("/workspaces/", "/", $2); print $2 }' || true)
have=$(git config "delphi.$self.version" || { [ -n "$old" ] && git config "delphi.$old.version"; } || echo 0.0.0)
pending=$(for f in .delphi/migrations/*.sh; do [ ! -e "$f" ] || echo "${f##*/}"; done | sort -t. -k1,1n -k2,2n -k3,3n)
while IFS= read -r f; do
  v=${f%%-*}
  [ -n "$f" ] || continue
  older "$have" "$v" || continue
  echo "setup: migrating $self to $v (.delphi/migrations/$f)"
  bash ".delphi/migrations/$f" </dev/null || { echo "setup: migration $f failed; do what it says, then re-run" >&2 && exit 1; }
  git config "delphi.$self.version" "$v" && have=$v
done <<EOF1
$pending
EOF1
! older "$have" "${here%% *}" || git config "delphi.$self.version" "${here%% *}"

list=$(awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  /^repos:/ { s = "repo"; next }
  /^references-git:/ { s = "ref"; next }
  /^workspaces:/ { s = "link"; next }
  /^[^[:space:]]/ { s = "" }
  s == "link" { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, ""); print s, $0; next }
  s { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); n = index($0, ":")
      if (n) print s, substr($0, 1, n - 1), substr($0, n + 1) }' workspace.yml)

readonly_copy() { # <dir> <url> [<ref>]: shallow, detached, push-disabled checkout at <dir>
  local dir=$1
  [ ! -f "$dir/.git" ] || { echo "setup: $dir is a worktree, not a read-only copy; skipping it" >&2 && return; }
  [ -d "$dir/.git" ] || { git init -q "$dir" && git -C "$dir" remote add origin "$2"; }
  git -C "$dir" remote set-url origin "$2"
  git -C "$dir" remote set-url --push origin DISABLED-read-only-copy
  if git -C "$dir" fetch -q --depth 1 origin "${3:-HEAD}" </dev/null &&
    git -C "$dir" checkout -q --detach FETCH_HEAD; then
    echo "$dir: at ${3:-default branch} ($(git -C "$dir" rev-parse --short HEAD))"
  else
    echo "setup: could not update $dir to ${3:-the default branch}" >&2
  fi
}

link() { # <name>|main: a clone of Delphi on that workspace's branch (ws/<name>), or main, at workspaces/<name>
  case "$1" in "$self") return 0 ;; "" | [-.]* | *. | *..* | *[!a-z0-9.-]*)
    echo "setup: skipping bad workspaces: entry '$1' (want a workspace's name, like s.app.argos.argos-dev, or main)" >&2 && return ;;
  esac
  local dir=workspaces/$1 ref=ws/$1
  [ "$1" != main ] || ref=main
  [ ! -f "$dir/.git" ] || { echo "setup: $dir is a worktree, not a clone; skipping it" >&2 && return; }
  if [ ! -d "$dir/.git" ]; then
    git clone -q --branch "$ref" "$(git remote get-url origin)" "$dir" </dev/null ||
      { echo "setup: could not clone $ref into $dir" >&2 && return; }
  elif [ "$(git -C "$dir" branch --show-current)" != "$ref" ]; then # switched away: back to its own branch first
    bash "$dir/.delphi/switch.sh" "$1" </dev/null >/dev/null ||
      { echo "setup: could not switch $dir back to $ref; left it as it is" >&2 && return; }
  fi
  git -C "$dir" pull -q --ff-only origin "$ref" </dev/null || echo "setup: could not pull $ref into $dir (see git -C $dir status)" >&2
  echo "$dir: on $ref ($(git -C "$dir" rev-parse --short HEAD))"
  [ ! -f "$dir/workspace.yml" ] || # its own setup, which skips its workspaces:
    bash "$dir/.delphi/setup.sh" </dev/null >/dev/null || echo "setup: $dir's own setup failed (bash $dir/.delphi/setup.sh)" >&2
}

[ -z "$inside" ] || ! grep -q '^link ' <<<"$list" || echo "setup: in $inside's workspaces/, so this workspace's workspaces: are skipped"
while read -r kind name url ref; do
  [ -n "$name" ] || continue
  if [ "$kind" = link ]; then [ -n "$inside" ] || link "$name"; continue; fi
  case "$name" in . | .. | *[!A-Za-z0-9._-]*) echo "setup: skipping unsafe repo name '$name'" >&2 && continue ;; esac
  if [ "$kind" = ref ]; then readonly_copy "references/$name" "$url" ${ref:+"$ref"} && continue; fi
  if [ -e "repos/$name" ]; then echo "repos/$name: already present"
  else git clone -q "$url" "repos/$name" </dev/null || echo "setup: could not clone $url into repos/$name" >&2
  fi
  store=worktrees/$name/.bare
  if [ ! -e "$store" ]; then
    git init -q --bare "$store"
    git -C "$store" remote add origin "$url"
    git -C "$store" fetch -q origin </dev/null
    git -C "$store" remote set-head origin -a >/dev/null </dev/null
  fi
  def=$(git -C "$store" symbolic-ref -q --short refs/remotes/origin/HEAD) ||
    { echo "setup: $store has no origin/HEAD; skipping its worktree" >&2 && continue; }
  def=${def#origin/}
  dest=worktrees/$name/$def
  if [ -e "$dest" ]; then continue
  elif git -C "$store" rev-parse -q --verify "refs/heads/$def" >/dev/null; then
    git -C "$store" worktree add -q "$PWD/$dest" "$def" || echo "setup: could not check out $dest" >&2
  else
    git -C "$store" worktree add -q --track -b "$def" "$PWD/$dest" "origin/$def"
  fi
done <<EOF2
$list
EOF2

exclude=$(git rev-parse --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
for d in /repos/ /worktrees/ /references/ /workspaces/ /.journal/ $(awk '/^[^[:space:]#]/ { s = /^park:/; next }
  s && /^[[:space:]]+-/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); print "/" $0 "/" }' workspace.yml) .DS_Store; do
  grep -qxF "$d" "$exclude" 2>/dev/null || echo "$d" >>"$exclude"
done
hook=$(git rev-parse --git-path hooks/post-checkout)
link=$(readlink "$hook" 2>/dev/null || true) # ours: this script, or an old link to (or copy of) a park.sh
if [ "${link%/.delphi/park.sh}" != "$link" ] || { [ -z "$link" ] && { [ ! -e "$hook" ] || grep -qF '.delphi/park.sh' "$hook"; }; }; then
  # A script, not a link: the clone's worktrees share one hook, and a link would run one checkout's park.sh for all
  mkdir -p "$(dirname "$hook")" && rm -f "$hook" && cat >"$hook" <<'EOF3' && chmod +x "$hook"
#!/bin/sh
# Delphi's post-checkout hook, written by .delphi/setup.sh: runs .delphi/park.sh as just checked out,
# in the worktree that checked out (git runs hooks at its root), so each runs its own branch's.
[ ! -f .delphi/park.sh ] || exec bash .delphi/park.sh "$@"
EOF3
else
  echo "setup: $hook is another hook; not installing .delphi/park.sh, so checkouts won't park repos/" >&2
fi
bash .delphi/plugins.sh >&2 || true # never a failure
