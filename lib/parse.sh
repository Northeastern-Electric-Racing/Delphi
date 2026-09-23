# parse.sh — strict YAML-subset parser (POSIX awk) and record accessors.
#
# Supported: full-line and trailing ' #' comments; top-level `key: value`; top-level `key:`
# followed by two-space-indented `- item` lines (list) or `sub: value` lines (one-level map).
# Anything else is a parse error reported as file:line.
#
# Output records (tab-separated):  scalar/list item -> key<TAB>value
#                                  map entry        -> key<TAB>sub<TAB>value

parse_yaml() {
  [ -f "$1" ] || die "no such file: $1"
  awk -v F="$1" '
    function trim(s) { sub(/^[ ]+/, "", s); sub(/[ ]+$/, "", s); return s }
    function unquote(s) { if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
    function nocomment(s,   i, rest) {
      if (s ~ /^[ ]*"/) {
        i = index(substr(s, index(s, "\"") + 1), "\"")
        if (i == 0) fail("unterminated quote")
        i += index(s, "\"")
        rest = substr(s, i + 1)
        if (rest ~ /^[ ]*$/ || rest ~ /^[ ]+#/) return substr(s, 1, i)
        fail("text after closing quote")
      }
      i = index(s, " #"); if (i > 0) s = substr(s, 1, i - 1)
      return s
    }
    function check(v) { if (v ~ /^[[{&*|>!]/) fail("unsupported YAML syntax: " v) }
    function fail(m) { printf "%s:%d: %s\n", F, NR, m > "/dev/stderr"; bad = 1; exit 1 }
    /\t/ { fail("tabs are not allowed") }
    /^[ ]*#/ || /^[ ]*$/ { next }
    /^[A-Za-z0-9_-]+:/ {
      k = $0; sub(/:.*/, "", k)
      if (k in seen) fail("duplicate key: " k); seen[k] = 1
      v = $0; sub(/^[^:]*:/, "", v); v = trim(nocomment(v)); check(v)
      if (v == "") { cur = k } else { print k "\t" unquote(v); cur = "" }
      next
    }
    /^  - / {
      if (cur == "") fail("list item without a parent key")
      v = trim(nocomment(substr($0, 5))); check(v)
      print cur "\t" unquote(v); next
    }
    /^  [A-Za-z0-9_-]+:/ {
      if (cur == "") fail("map entry without a parent key")
      s = substr($0, 3); k = s; sub(/:.*/, "", k)
      v = s; sub(/^[^:]*:/, "", v); v = trim(nocomment(v)); check(v)
      if (v == "") fail("nested maps are not supported")
      print cur "\t" k "\t" unquote(v); next
    }
    { fail("unsupported indentation or syntax") }
  ' "$1"
}

# Accessors take the records string produced by parse_yaml.
yaml_get()  { printf '%s\n' "$1" | awk -F'\t' -v k="$2" 'NF == 2 && $1 == k { print $2; exit }'; }
yaml_list() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" 'NF == 2 && $1 == k { print $2 }'; }
yaml_map()  { printf '%s\n' "$1" | awk -F'\t' -v k="$2" 'NF == 3 && $1 == k { print $2 "\t" $3 }'; }
yaml_keys() { printf '%s\n' "$1" | awk -F'\t' 'NF >= 2 { print $1 }' | sort -u; }
