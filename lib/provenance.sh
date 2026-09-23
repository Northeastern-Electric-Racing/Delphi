# provenance.sh — which harness, model, and effort produced a change.
#
# Resolution per field: CLI flag -> DELPHI_* env (set by `workspace open`) -> adapter fallback
# -> interactive prompt (accepts "none") -> error. Never records "unknown".
# Results: PROV_HARNESS PROV_MODEL PROV_EFFORT. Extra trailer lines go in PROV_EXTRA; extra
# table rows (other sessions that contributed) go in PROV_ROWS.

PROV_EXTRA=""
PROV_ROWS=""

# provenance_resolve <flag-model> <flag-effort> <adapter>
provenance_resolve() {
  local fb="" fb_h fb_m fb_e
  load_harness "$3"
  fb=$(harness_provenance 2>/dev/null || true)
  fb_h=$(printf '%s\n' "$fb" | sed -n 1p)
  fb_m=$(printf '%s\n' "$fb" | sed -n 2p)
  fb_e=$(printf '%s\n' "$fb" | sed -n 3p)
  PROV_HARNESS=${DELPHI_HARNESS:-$fb_h}
  PROV_MODEL=${1:-${DELPHI_MODEL:-$fb_m}}
  PROV_EFFORT=${2:-${DELPHI_EFFORT:-$fb_e}}
  [ -n "$PROV_HARNESS" ] || PROV_HARNESS=$(_prov_ask harness DELPHI_HARNESS) || exit 1
  [ -n "$PROV_MODEL" ]   || PROV_MODEL=$(_prov_ask model DELPHI_MODEL --model) || exit 1
  [ -n "$PROV_EFFORT" ]  || PROV_EFFORT=$(_prov_ask effort DELPHI_EFFORT --effort) || exit 1
}

# _prov_ask <field> <env-var> [flag]
_prov_ask() {
  local a
  is_tty || die "provenance: $1 unknown — ${3:+pass $3 or }set $2"
  a=$(ask "Which $1 made this change? ('none' if no AI was used)") || exit 1
  [ -n "$a" ] || die "provenance: $1 is required"
  printf '%s\n' "$a"
}

provenance_trailers() {
  printf 'Delphi-Harness: %s\nDelphi-Model: %s\nDelphi-Effort: %s\n' "$PROV_HARNESS" "$PROV_MODEL" "$PROV_EFFORT"
  [ -n "$PROV_EXTRA" ] && printf '%s\n' "$PROV_EXTRA"
  return 0
}

# provenance_table: markdown table of this session plus PROV_ROWS ("harness|model|effort" lines).
provenance_table() {
  printf '| Harness | Model | Effort |\n|---|---|---|\n| %s | %s | %s |\n' "$PROV_HARNESS" "$PROV_MODEL" "$PROV_EFFORT"
  [ -n "${PROV_ROWS:-}" ] && printf '%s\n' "$PROV_ROWS" | while IFS='|' read -r h m e; do
    printf '| %s | %s | %s |\n' "$h" "$m" "$e"
  done
  return 0
}
