#!/usr/bin/env bash
# ci/check.sh [<dir> [<base>]]: validate Delphi (CI runs it on PRs to main, against main; sync.sh on
# each proposal). Rules: a workspace is software/**/workspaces/<leaf>/ with a workspace.yml; its name
# is its folder's path without `workspaces/` (software/x/workspaces/y -> software/x/y; branch
# ws/<name>), in lowercase letters, digits, '-' and '/', and no name is a folder of another's (git
# can't have both ws/a and ws/a/b); workspaces never nest; no symlinks under
# software/; no workspace (nor the template) has its own .delphi/ (sync puts main's on every ws/*
# branch); .delphi/manifest.yml lists itself, every file in .delphi/ but `versions`, and only files
# git tracks; its `version:` and the hash of those files (.delphi/version.sh) are the last line of
# .delphi/versions, whose versions rise; each .delphi/migrations/<version>-<slug>.sh has its line
# there, bumps MAJOR (MINOR while 0.x) over the line before, and starts like every script; against
# <base>, .delphi/versions only gains lines and released migrations are unchanged; each manifest file
# outside .delphi/ (the workflow) is the same in templates/workspace/ and every workspace; workspace.yml is `name: <its name>`,
# `harness: <adapter>`, an optional `repos:` map of `<name>: <git-url>`, and an optional
# `references-git:` map of `<name>: <git-url> [<ref>]`; names are unique across both; and an optional
# `workspaces:` list of `- ws/<name>` (a workspace on main) or `- main`, without duplicates or the workspace itself, and an
# optional `plugins:` list of `- <scope>[.<set>]` without duplicates. A project's
# defaults/workspace.yml is the same without `name:`. The files ci/plugins.sh generates
# (.claude-plugin/marketplace.json, each workspace's .claude/settings.json) are up to date.
# Lists every problem; exits 1 if any.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
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
while IFS= read -r msg; do bad "${msg#plugins: }"; done < <(bash "$here/plugins.sh" --check . 2>&1 >/dev/null || true)

manifest() { # <workspace.yml> [<name>]: without <name> (a defaults/ manifest), `name:` is not allowed
  while IFS= read -r msg; do bad "$1: $msg"; done < <(awk -v want="${2:-}" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    want != "" && /^name:/ { v = $0; sub(/^name:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
                  if (v != want) print "name is \"" v "\", want \"" want "\" (the folder path without workspaces/)"
                  if (nm++) print "duplicate name"; r = 0; next }
    /^harness:/ { v = $0; sub(/^harness:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
                  if (v == "") print "harness is empty"; if (h++) print "duplicate harness"; r = 0; next }
    /^repos:[[:space:]]*(#.*)?$/ { r = 1; next }
    /^references-git:[[:space:]]*(#.*)?$/ { r = 2; next }
    /^links:/ { print "links: is now workspaces: (entries `  - ws/<name>` or `  - main`)"; r = 3; next }
    /^workspaces:[[:space:]]*(#.*)?$/ { r = 3; next }
    /^plugins:[[:space:]]*(#.*)?$/ { r = 4; next }
    r == 4 && /^[[:space:]]/ {
      if ($0 !~ /^[[:space:]]+-[[:space:]]+[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)?[[:space:]]*(#.*)?$/) {
        print "bad plugins entry (want `  - <scope>[.<set>]`, e.g. argos.testing): " $0; next }
      v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if (sets[v]++) print "duplicate plugin set: " v
      next }
    r == 3 && /^[[:space:]]/ {
      if ($0 !~ /^[[:space:]]+-[[:space:]]+(main|ws\/[a-z0-9][a-z0-9\/-]*)[[:space:]]*(#.*)?$/ || $0 ~ /\/\/|\/[[:space:]]*(#.*)?$/) {
        print "bad workspaces entry (want `  - ws/<name>` or `  - main`): " $0; next }
      v = $0; sub(/^[[:space:]]+-[[:space:]]+/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      if (v == "ws/" want) print "lists itself: " v
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
    END { if (!h) print "harness is missing"; if (want != "" && !nm) print "name is missing" }' "$1")
  while IFS= read -r v; do listed="$listed $1|${v#ws/}"; done < <(awk '/^workspaces:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-[[:space:]]+ws\// { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); print }' "$1")
}

folders="" names="" listed=""
while IFS= read -r f; do
  folder=${f%/workspace.yml}
  name=${folder%/workspaces/*}/${folder##*/}
  case "$(dirname "$folder")" in */workspaces) ;; *)
    bad "$f: must be at software/**/workspaces/<name>/workspace.yml" && continue ;;
  esac
  case "$folder" in *[!A-Za-z0-9._/-]*) bad "$folder: path has unsafe characters" && continue ;; esac
  case "$name" in */-* | *[!a-z0-9/-]*) bad "$folder: name $name must be lowercase letters, digits, '-' and '/'" ;; esac
  for other in $names; do
    case "$name/" in "$other"/*) bad "$folder: ws/$name can't be a branch while ws/$other is (git can't hold both); rename one" ;; esac
    case "$other/" in "$name"/*) bad "$folder: ws/$name can't be a branch while ws/$other is (git can't hold both); rename one" ;; esac
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
done < <(find software -name workspace.yml -type f \( ! -path '*/defaults/workspace.yml' -o -path '*/workspaces/defaults/*' \) 2>/dev/null | sort)
while IFS= read -r f; do manifest "$f"; done \
  < <(find software -path '*/defaults/workspace.yml' ! -path '*/workspaces/defaults/*' -type f 2>/dev/null)
for l in $listed; do
  case " $names " in *" ${l#*|} "*) ;; *) bad "${l%%|*}: workspaces: lists ws/${l#*|}, which isn't a workspace on main" ;; esac
done

[ "$problems" = 0 ] || { echo "check: $problems problem(s)" >&2 && exit 1; }
echo "check: ok"
