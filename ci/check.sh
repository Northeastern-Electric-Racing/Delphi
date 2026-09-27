#!/usr/bin/env bash
# ci/check.sh [<dir>]: validate Delphi (CI runs it on PRs to main; sync.sh on each proposal). Rules:
# a workspace is software/**/workspaces/<name>/ with a workspace.yml; names are lowercase letters,
# digits, and '-', unique repo-wide; workspaces never nest; no symlinks under software/; each
# workspace's .delphi/*.sh and .github/workflows/delphi.yml match templates/workspace/, and the
# template workflow matches .github/workflows/delphi.yml; workspace.yml is `harness: <adapter>` plus
# an optional `repos:` map of `<name>: <git-url>`. Lists every problem; exits 1 if any.
set -euo pipefail
cd "${1:-.}"
problems=0
bad() { echo "check: $*" >&2 && problems=$((problems + 1)); }
tpl=templates/workspace
managed=".delphi/setup.sh .delphi/new-worktree.sh .github/workflows/delphi.yml"

[ -d software ] || bad "software/ is missing"
cmp -s .github/workflows/delphi.yml $tpl/.github/workflows/delphi.yml ||
  bad "$tpl/.github/workflows/delphi.yml: differs from .github/workflows/delphi.yml"
while IFS= read -r f; do bad "$f: symlinks are not allowed under software/"; done \
  < <(find software -type l 2>/dev/null)

folders=""
while IFS= read -r f; do
  folder=${f%/workspace.yml}
  name=${folder##*/}
  case "$(dirname "$folder")" in */workspaces) ;; *)
    bad "$f: must be at software/**/workspaces/<name>/workspace.yml" && continue ;;
  esac
  case "$folder" in *[!A-Za-z0-9._/-]*) bad "$folder: path has unsafe characters" && continue ;; esac
  case "$name" in -* | *[!a-z0-9-]*) bad "$folder: name must be lowercase letters, digits, and '-'" ;; esac
  for other in $folders; do
    [ "${other##*/}" != "$name" ] || bad "$folder: name '$name' is also used by $other"
    case "$folder/" in "$other"/*) bad "$folder: nested inside workspace $other" ;; esac
    case "$other/" in "$folder"/*) bad "$other: nested inside workspace $folder" ;; esac
  done
  folders="$folders $folder"
  for m in $managed; do cmp -s "$tpl/$m" "$folder/$m" || bad "$folder/$m: differs from $tpl/$m"; done
  while IFS= read -r msg; do bad "$f: $msg"; done < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^harness:/ { v = $0; sub(/^harness:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
                  if (v == "") print "harness is empty"; if (h++) print "duplicate harness"; r = 0; next }
    /^repos:[[:space:]]*(#.*)?$/ { r = 1; next }
    r && /^[[:space:]]/ {
      if ($0 !~ /^[[:space:]]+[A-Za-z0-9._-]+:[[:space:]]+[^[:space:]"#]+[[:space:]]*(#.*)?$/) {
        print "bad repos entry (want `  <name>: <git-url>`): " $0; next }
      n = $1; sub(/:$/, "", n)
      if (n == "." || n == "..") print "bad repo name: " n
      if (seen[n]++) print "duplicate repo: " n
      next }
    { print "unexpected line: " $0 }
    END { if (!h) print "harness is missing" }' "$f")
done < <(find software -name workspace.yml -type f 2>/dev/null | sort)

[ "$problems" = 0 ] || { echo "check: $problems problem(s)" >&2 && exit 1; }
echo "check: ok"
