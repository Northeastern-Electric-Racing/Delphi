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
    function missing(id) { print "harness: " target ": missing Claude mapping for " id " in " file " (translated line " NR ")" > "/dev/stderr"; failed = 1 }
    function native_skills(s, at, out) {
      while (match(s, /(^|[^A-Za-z0-9_.\/-])[.]claude\/skills/)) {
        at = RSTART + RLENGTH - 14
        out = out substr(s, 1, at - 1) skills; s = substr(s, at + 14)
      }
      return out s
    }
    function repository_file(s, at, before, after) {
      before = tolower(substr(s, 1, at - 1)); after = tolower(substr(s, at + 9))
      return before ~ /(^|[^a-z])(repo|repository|worktree)(\047s|[ -]local)?([[:space:]]+own)?[[:space:]]*$/ ||
        after ~ /^[[:space:]]+(in|from|of)[[:space:]]+(the[[:space:]]+)?(code[[:space:]]+)?(repo|repository|worktree)([^a-z]|$)/
    }
    function refs(s, code, start, at, size, before, after, id, active, out) {
      start = 1
      while (!code && match(substr(s, start), /CLAUDE[.]md/)) {
        at = start + RSTART - 1; before = substr(s, at - 1, 1); after = substr(s, at + 9, 1)
        active = (at == 1 || before !~ /[A-Za-z0-9_.\/-]/) && after !~ /[A-Za-z0-9_\/-]/ &&
          (after != "." || substr(s, at + 10, 1) !~ /[A-Za-z0-9]/) && !repository_file(s, at)
        out = out substr(s, start, at - start)
        if (active && check && instruction != "CLAUDE.md") missing("CLAUDE.md")
        out = out (active && !check ? instruction : "CLAUDE.md"); start = at + 9
      }
      s = out substr(s, start); start = 1; out = ""
      # Always inspect boundaries in the original string, including after an unmatched path segment.
      while (match(substr(s, start), /\/[a-z][a-z0-9-]*/)) {
        at = start + RSTART - 1; size = RLENGTH; id = substr(s, at + 1, size - 1)
        before = substr(s, at - 1, 1); after = substr(s, at + size, 1)
        active = id in known && (at == 1 || before ~ /[[:space:](]/) && after != "/" &&
          (after != "." || substr(s, at + size + 1, 1) !~ /[A-Za-z0-9]/) && (!code || at == 1)
        out = out substr(s, start, at - start)
        if (active && check && ref != "/%s") missing("/" id)
        out = out (active && !check ? sprintf(ref, id) : "/" id); start = at + size
      }
      return out substr(s, start)
    }
    function spans(s, out, marker, tail, search, closing, size, offset) {
      while (match(s, /`+/)) {
        offset = RSTART; marker = substr(s, offset, RLENGTH); tail = substr(s, offset + RLENGTH)
        search = tail; closing = 0; size = 0
        while (match(search, /`+/)) {
          if (RLENGTH == length(marker)) { closing = size + RSTART; break }
          size += RSTART + RLENGTH - 1; search = substr(search, RSTART + RLENGTH)
        }
        if (!closing) break
        out = out refs(substr(s, 1, offset - 1), 0) marker refs(substr(tail, 1, closing - 1), 1) marker
        s = substr(tail, closing + length(marker))
      }
      return out refs(s, 0)
    }
    function fence_line(s, marker, size, suffix) {
      sub(/^[[:space:]]*/, "", s)
      if (!match(s, /^(```+|~~~+)/)) return 0
      marker = substr(s, 1, 1); size = RLENGTH; suffix = substr(s, size + 1)
      if (!fence) { fence = marker; fence_size = size; return 1 }
      if (fence == marker && size >= fence_size && suffix ~ /^[[:space:]]*$/) { fence = ""; return 1 }
      return 0
    }
    BEGIN { n = split(ids, names, " "); for (i = 1; i <= n; i++) known[names[i]] = 1 }
    {
      line = $0
      if (fence_line(line)) { print line; next }
      if (!check) {
        # Feature bullets are selected by identifiers, never by their English wording.
        if (!fence && line ~ /^[-*] / && index(line, "/ws-delphi") && pane != "") {
          if (pane != "drop") print "- " pane
          next
        }
        if (!fence && line ~ /^[-*] / && index(line, "`delphi` mod") && reload != "") { print "- " reload; next }
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
      # Code filenames and explicitly repository-scoped references are literal; backticked skill calls still adapt.
      if (!fence) line = spans(line)
      if (check) {
        rest = line
        while (match(rest, /mcp__[A-Za-z0-9_]+|CLAUDE_[A-Za-z0-9_]+|(^|[^A-Za-z0-9_.\/-])[.]claude([\/`[:space:]]|$)|(~|\$HOME|\$\{HOME\})\/[.]claude([\/`[:space:]]|$)|\/ws-delphi|pull_request_read|playwright-cdp|GitHub MCP server|Claude Code|`delphi` mod|subagent_type[[:space:]]*=[[:space:]]*Explore|(^|[^A-Za-z0-9_])(WebFetch|ultrathink)([^A-Za-z0-9_]|$)|claude[[:space:]]+plugin[[:space:]]+install/)) {
          missing(substr(rest, RSTART, RLENGTH)); rest = substr(rest, RSTART + RLENGTH)
        }
      }
      print line
    }
    END { exit failed }'
}
