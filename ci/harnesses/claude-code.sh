#!/usr/bin/env bash
# shellcheck disable=SC2034
# Claude-native paths and CI capabilities; read by the shared registry.
set -euo pipefail
instruction=CLAUDE.md
instruction_base=''
instruction_template=templates/workspace/CLAUDE.md
skills=.claude/skills
native='.claude'
protected='.claude/settings.json'
plugins=claude
settings_file=.claude/settings.json
settings_generator=ci/plugins.sh
bootstrap=hook
skill_ref='/%s'
github_tool=''
github_integration=''
browser_tool=''
pane_guidance=''
reload_guidance=''

translate_skill() { cat "$1"; }

claude_identifiers() { # [check]: Claude's identifier contract, shared by target translators and leak validation
  # shellcheck disable=SC2154 # target, file and the skill catalog come from the registry's translator scope
  awk -v check="${1:-}" -v target="$target" -v file="$file" -v instruction="$instruction" \
    -v skills="$skills" -v ref="$skill_ref" -v ids="$harness_skill_names" \
    -v github="$github_tool" -v integration="$github_integration" -v browser="$browser_tool" \
    -v pane="$pane_guidance" -v reload="$reload_guidance" '
    function literal(s, from, to, at, out) {
      while ((at = index(s, from))) { out = out substr(s, 1, at - 1) to; s = substr(s, at + length(from)) }
      return out s
    }
    function missing(id) { print "harness: " target ": missing Claude mapping for " id " in " file ":" NR > "/dev/stderr"; failed = 1 }
    function native_skills(s, at, out) {
      while (match(s, /(^|[^A-Za-z0-9_.\/-])[.]claude\/skills/)) {
        at = RSTART + RLENGTH - 14
        out = out substr(s, 1, at - 1) skills; s = substr(s, at + 14)
      }
      return out s
    }
    BEGIN { n = split(ids, names, " "); for (i = 1; i <= n; i++) known[names[i]] = 1 }
    {
      line = $0
      if (!check) {
        # Feature bullets are selected by identifiers, never by their English wording.
        if (line ~ /^[-*] / && index(line, "/ws-delphi") && pane != "") {
          if (pane != "drop") print "- " pane
          next
        }
        if (line ~ /^[-*] / && index(line, "`delphi` mod") && reload != "") { print "- " reload; next }
        if (integration != "") line = literal(line, "GitHub MCP server", integration)
        if (github != "") {
          line = literal(line, "mcp__github__pull_request_read", github)
          line = literal(line, "pull_request_read", github)
        }
        if (browser != "") {
          line = literal(line, "`playwright-cdp`", "`" browser "`")
          line = literal(line, "`playwright`", "`" browser "`")
        }
        line = native_skills(line)
      }
      # Qualified code-repository filenames are literal paths, not workspace instruction identifiers.
      rest = line; out = ""
      while (match(rest, /(^|[^A-Za-z0-9_.\/-])CLAUDE[.]md/)) {
        at = RSTART + RLENGTH - 9
        out = out substr(rest, 1, at - 1)
        if (check) { if (instruction != "CLAUDE.md") missing("CLAUDE.md"); out = out "CLAUDE.md" }
        else out = out instruction
        rest = substr(rest, at + 9)
      }
      line = out rest; rest = line; out = ""
      while (match(rest, /(^|[[:space:]`(])\/[a-z][a-z0-9-]*/)) {
        at = RSTART; token = substr(rest, at, RLENGTH); slash = index(token, "/")
        id = substr(token, slash + 1); following = substr(rest, at + RLENGTH, 1)
        active = id in known && following != "/" && (following != "." || substr(rest, at + RLENGTH + 1, 1) !~ /[A-Za-z0-9]/)
        out = out substr(rest, 1, at - 1) substr(token, 1, slash - 1)
        if (active && check && ref != "/%s") missing("/" id)
        out = out (active && !check ? sprintf(ref, id) : "/" id)
        rest = substr(rest, at + RLENGTH)
      }
      line = out rest
      if (check) {
        if (match(line, /mcp__[A-Za-z0-9_]+|CLAUDE_[A-Za-z0-9_]+|(^|[^A-Za-z0-9_.\/-])[.]claude([\/`[:space:]]|$)|\/ws-delphi|pull_request_read|playwright-cdp|GitHub MCP server|Claude Code|`delphi` mod/)) missing(substr(line, RSTART, RLENGTH))
      }
      print line
    }
    END { exit failed }'
}
