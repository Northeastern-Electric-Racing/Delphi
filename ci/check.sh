#!/usr/bin/env bash
# ci/check.sh [<dir> [<base>]]: validate docs/design.md's workspace, source and runtime contracts.
# Main owns native files/settings; inherited copies and ledgers are branch-only. Checks never write.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=ci/inherit.sh
source "$here/inherit.sh"
cd "${1:-.}"
base=${2:-}
problems=0
bad() { echo "check: $*" >&2 && problems=$((problems + 1)); }
tpl=templates/workspace

[ -d software ] || bad "software/ is missing"
[ -f .delphi/manifest.yml ] && [ -f .delphi/version.sh ] || bad ".delphi/manifest.yml or .delphi/version.sh is missing"
files=$(bash .delphi/version.sh --files 2>/dev/null || true)
read -r version hash < <(bash .delphi/version.sh 2>/dev/null || echo "none none")
echo "$version" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+' || bad ".delphi/manifest.yml: version '$version' is not MAJOR.MINOR.PATCH"
echo "$files" | grep -qx .delphi/manifest.yml || bad ".delphi/manifest.yml: must list itself"
for f in $files; do git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || bad "$f: listed in .delphi/manifest.yml but missing (or not in git)"; done
for f in $(git ls-files .delphi); do
  [ "$f" = .delphi/versions ] || echo "$files" | grep -qxF "$f" || bad "$f: in .delphi/ but not listed in .delphi/manifest.yml"
done
managed=$(echo "$files" | grep -v '^\.delphi/' || true) # the rest of Delphi's files: the same in the template and every workspace
for m in $managed; do cmp -s "$m" "$tpl/$m" || bad "$tpl/$m: differs from $m"; done

migs=""
for f in .delphi/migrations/*; do
  [ -e "$f" ] || continue
  n=${f##*/}
  echo "$n" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9-]+\.sh' || { bad "$f: name it <MAJOR.MINOR.PATCH>-<slug>.sh" && continue; }
  { [ "$(sed -n 1p "$f")" = "#!/usr/bin/env bash" ] && grep -qx 'set -euo pipefail' "$f"; } ||
    bad "$f: start it with #!/usr/bin/env bash and set -euo pipefail"
  case " $migs " in *" ${n%%-*} "*) bad "$f: one migration per version" ;; esac
  migs="$migs ${n%%-*}"
done
while IFS= read -r msg; do bad ".delphi/versions: $msg"; done < <(awk -v migs="$migs" '
  function p(v, i, a) { split(v, a, "."); return a[i] + 0 }
  function above(a, b) { return p(a, 1) != p(b, 1) ? p(a, 1) > p(b, 1) : p(a, 2) != p(b, 2) ? p(a, 2) > p(b, 2) : p(a, 3) > p(b, 3) }
  BEGIN { n = split(migs, m, " "); for (i = 1; i <= n; i++) mig[m[i]] = 1 }
  /^#/ || /^[[:space:]]*$/ { next }
  $1 !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ || $2 !~ /^[0-9a-f]+$/ || length($2) != 12 {
    print "bad line (want `<MAJOR.MINOR.PATCH> <hash> <what changed>`): " $0; next }
  { v = $1
    if (prev != "" && !above(v, prev)) print v " is not above " prev
    if (prev != "" && (v in mig) && !(p(v, 1) > p(prev, 1) || (p(v, 1) == 0 && p(v, 2) > p(prev, 2))))
      print v " has a migration, so it must bump " (p(v, 1) ? "MAJOR" : "MINOR (MAJOR from 1.0.0)") " over " prev
    seen[v] = 1; prev = v }
  END { for (v in mig) if (!(v in seen)) print "no line for migrations/" v "-*.sh" }' .delphi/versions 2>/dev/null)
last=$(grep -v '^#' .delphi/versions 2>/dev/null | grep . | tail -n 1 | cut -d' ' -f1,2 || true)
if [ "$last" != "$version $hash" ]; then
  if [ "${last%% *}" = "$version" ]; then
    bad "Delphi's files changed since $version: bump version: in .delphi/manifest.yml (see its header), then add the line \`bash .delphi/version.sh\` prints to .delphi/versions"
  else bad ".delphi/versions: add \`$version $hash <what changed>\` (now ends at ${last:-nothing})"; fi
fi
if [ -n "$base" ] && git cat-file -e "$base:.delphi/versions" 2>/dev/null; then
  n=$(git show "$base:.delphi/versions" | wc -l)
  git show "$base:.delphi/versions" | cmp -s - <(head -n $((n)) .delphi/versions) ||
    bad ".delphi/versions: changes lines already on $base; only add lines"
  for f in $(git ls-tree -r --name-only "$base" -- .delphi/migrations); do
    git show "$base:$f" | cmp -s - "$f" || bad "$f: released in $base; add a new version's migration instead of changing it"
  done
fi
[ ! -e $tpl/.delphi ] || bad "$tpl/.delphi: scripts live only in the root .delphi/"
while IFS= read -r f; do bad "$f: symlinks are not allowed under software/"; done \
  < <(find software -type l 2>/dev/null)
while IFS= read -r at; do bad "$at: names a harness variable; call scripts as \`bash scripts/<script>.sh\` (they read \$DELPHI_ROOT)"; done < <(
  git ls-files '*SKILL.md' | while IFS= read -r f; do # frontmatter is harness metadata; the body is shared
    awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { f = 0; next } !f && /\$\{CLAUDE_/ { print FILENAME ":" FNR; exit }' "$f"
  done)
if messages=$(bash "$here/render.sh" --check . 2>&1); then :
elif [ -z "$messages" ]; then bad "inherited output validation failed"; fi
while IFS= read -r msg; do [ -z "$msg" ] || bad "$msg"; done <<<"$messages"

manifest() { # <workspace.yml> [<name>]: without <name> (a workspace-defaults/ manifest), `name:` is not allowed
  while IFS= read -r msg; do bad "$1: $msg"; done < <(awk -v want="${2:-}" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    want != "" && /^name:/ { v = $0; sub(/^name:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
                  if (v != want) print "name is \"" v "\", want \"" want "\" (.delphi/names.sh)"
                  if (nm++) print "duplicate name"; r = 0; next }
    /^harness:/ { v = $0; sub(/^harness:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
                  if (v == "") print "harness is empty"; if (h++) print "duplicate harness"; r = 0; next }
    /^repos:[[:space:]]*(#.*)?$/ { r = 1; next }
    /^references-git:[[:space:]]*(#.*)?$/ { r = 2; next }
    /^links:/ { print "links: is now workspaces: (entries `  - <name>` or `  - main`)"; r = 3; next }
    /^workspaces:[[:space:]]*(#.*)?$/ { r = 3; next }
    /^plugins:[[:space:]]*(#.*)?$/ { r = 4; next }
    /^opt-out:[[:space:]]*(#.*)?$/ { r = 5; next }
    /^park:[[:space:]]*(#.*)?$/ { r = 6; next }
    r == 6 && /^[[:space:]]/ {
      v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if ($0 !~ /^[[:space:]]+-[[:space:]]+[A-Za-z0-9._-]+[[:space:]]*(#.*)?$/ || v ~ /^(\.|\.\.|\.git|\.delphi)$/) {
        print "bad park entry (want `  - <folder at the root>`, not .git or .delphi): " $0; next }
      if (pk[v]++) print "duplicate park entry: " v
      next }
    r == 5 && /^[[:space:]]/ {
      if ($0 !~ /^[[:space:]]+-[[:space:]]+[A-Za-z0-9._@+][A-Za-z0-9._/@+-]*[[:space:]]*(#.*)?$/ || $0 ~ /(^|[[:space:]\/])\.\.(\/|[[:space:]]|$)/) {
        print "bad opt-out entry (want `  - <path it inherits>`, e.g. .claude/skills/journal): " $0; next }
      v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if (opt[v]++) print "duplicate opt-out: " v
      next }
    r == 4 && /^[[:space:]]/ {
      if ($0 !~ /^[[:space:]]+-[[:space:]]+[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)?[[:space:]]*(#.*)?$/) {
        print "bad plugins entry (want `  - <scope>[.<set>]`, e.g. argos.testing): " $0; next }
      v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if (sets[v]++) print "duplicate plugin set: " v
      next }
    r == 3 && /^[[:space:]]/ {
      if ($0 !~ /^[[:space:]]+-[[:space:]]+[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)*[[:space:]]*(#.*)?$/) {
        print "bad workspaces entry (want `  - <name>`, e.g. s.app.argos.argos-dev, or `  - main`): " $0; next }
      v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if (v == want) print "lists itself: " v
      if (listed[v]++) print "duplicate workspace: " v
      next }
    r == 1 && /^[[:space:]]/ && $0 !~ /^[[:space:]]+[A-Za-z0-9._-]+:[[:space:]]+[^[:space:]"#]+[[:space:]]*(#.*)?$/ {
      print "bad repos entry (want `  <name>: <git-url>`): " $0; next }
    r == 2 && /^[[:space:]]/ && $0 !~ /^[[:space:]]+[A-Za-z0-9._-]+:[[:space:]]+[^[:space:]"#]+([[:space:]]+[A-Za-z0-9@._\/-]+)?[[:space:]]*(#.*)?$/ {
      print "bad references-git entry (want `  <name>: <git-url> [<ref>]`): " $0; next }
    r && /^[[:space:]]/ {
      n = $1; sub(/:$/, "", n)
      if (n == "." || n == "..") print "bad repo name: " n
      if (seen[n]++) print "duplicate repo: " n
      next }
    { print "unexpected line: " $0 }
    END { if (want != "" && !h) print "harness is missing"; if (want != "" && !nm) print "name is missing" }' "$1")
  local adapter instruction foreign plugins
  adapter=$(awk '/^harness:/ { print $2; exit }' "$1")
  if [ -n "$adapter" ]; then
    harness_exists "$adapter" || { bad "$1: unknown harness '$adapter'"; return; }
    plugins=$(harness_field "$adapter" plugins)
    instruction=$(harness_field "$adapter" instruction)
    foreign=$(harness_foreign "$adapter")
    if [ "$plugins" = none ] && awk '/^plugins:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 } s && /^[[:space:]]+-/ { found = 1 } END { exit !found }' "$1"; then
      bad "$1: $adapter does not support Delphi plugin sets"
    fi
    if [ -n "${2:-}" ]; then
      [ -f "${1%/*}/$instruction" ] || bad "${1%/*}/$instruction: required for $adapter"
      for incompatible in $foreign; do
        [ ! -e "${1%/*}/$incompatible" ] || bad "${1%/*}/$incompatible: belongs to a different harness"
      done
    fi
  fi
  while IFS= read -r v; do listed="$listed $1|$v"; done < <(awk '/^workspaces:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-[[:space:]]+/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); if ($0 != "main") print }' "$1")
}

while IFS= read -r d; do
  case "$d" in */workspaces/*) bad "$d: belongs in an org or project folder, not under workspaces/" ;; esac
  for f in $(harness_protected) workspace.yml workspace.generated .delphi $managed; do
    [ ! -e "$d/$f" ] || bad "$d/$f: each workspace has its own; it can't be inherited"
  done
done < <(find software -type d -name workspace-inherit 2>/dev/null | sort)
while IFS= read -r d; do
  case "$d" in */workspaces/*) continue ;; esac
  if format=$(source_format "$d" 2>/dev/null); then
    if ! messages=$(bundle_files "$d" "$format" 2>&1 >/dev/null); then bad "$messages"; fi
  else bad "$d/source.yml: declare one supported source format"; fi
done < <(find software -type d \( -name workspace-defaults -o -name workspace-inherit \) 2>/dev/null | sort)
while IFS= read -r d; do
  case "$d" in */workspaces/*) continue ;; esac
  format=$(source_format "$d" 2>/dev/null) || continue
  skills=$(harness_field "$format" skills)
  [ -d "$d/$skills" ] || continue
  for skill in "$d/$skills"/*; do
    [ ! -e "$skill" ] || [ -f "$skill/SKILL.md" ] || bad "$skill: shared skills need <name>/SKILL.md"
  done
done < <(find software -type d -name workspace-inherit 2>/dev/null)
while IFS= read -r d; do
  [ ! -d "${d%/workspaces}/defaults" ] || bad "${d%/workspaces}/defaults: renamed workspace-defaults/"
done < <(find software -type d -name workspaces 2>/dev/null)

while IFS= read -r f; do
  s=$(cat "$f")
  case "$s" in "" | -* | *[!a-z0-9-]*) bad "$f: want one line of lowercase letters, digits and '-' (the folder's short name)" ;; esac
done < <(find software -name short-name -type f 2>/dev/null | sort)
all=$(bash .delphi/names.sh 2>/dev/null || true) # <name> <folder>
folders="" names="" listed=""
while IFS= read -r f; do
  case "$f" in
    */workspaces/*) ;; # a workspace may itself be named workspace-defaults
    */workspace-inherit/* | */workspace-defaults/*) continue ;;
  esac
  folder=${f%/workspace.yml}
  case "$(dirname "$folder")" in */workspaces) ;; *)
    bad "$f: must be at software/**/workspaces/<leaf>/workspace.yml" && continue ;;
  esac
  case "$folder" in *[!A-Za-z0-9._/-]*) bad "$folder: path has unsafe characters" && continue ;; esac
  case "${folder##*/}" in -* | *[!a-z0-9-]*) bad "$folder: its folder name must be lowercase letters, digits and '-'" ;; esac
  name=$(echo "$all" | awk -v f="$folder" '$2 == f { print $1 }')
  for other in $names; do
    [ "$other" != "$name" ] || bad "$folder: another workspace is named $name too (names are unique); change a short-name or rename a folder"
  done
  names="$names $name"
  for other in $folders; do
    case "$folder/" in "$other"/*) bad "$folder: nested inside workspace $other" ;; esac
    case "$other/" in "$folder"/*) bad "$other: nested inside workspace $folder" ;; esac
  done
  folders="$folders $folder"
  [ ! -e "$folder/.delphi" ] || bad "$folder/.delphi: managed in the root .delphi/ on main; remove it"
  for m in $managed; do cmp -s "$tpl/$m" "$folder/$m" || bad "$folder/$m: differs from $tpl/$m"; done
  manifest "$f" "$name"
done < <(find software -name workspace.yml -type f 2>/dev/null | sort)
while IFS= read -r f; do manifest "$f"; done \
  < <(find software -path '*/workspace-defaults/workspace.yml' ! -path '*/workspaces/workspace-defaults/*' -type f 2>/dev/null)
for l in $listed; do
  case " $names " in *" ${l#*|} "*) ;; *) bad "${l%%|*}: workspaces: lists ${l#*|}, which isn't a workspace on main" ;; esac
done

[ "$problems" = 0 ] || { echo "check: $problems problem(s)" >&2 && exit 1; }
echo "check: ok"
