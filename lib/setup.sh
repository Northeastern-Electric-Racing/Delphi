# setup.sh — `delphi setup [dir]`: write a `delphi` wrapper into dir (default ~/.local/bin).
# A wrapper, not a symlink: Git Bash's ln -s copies by default.

setup_main() {
  [ $# -le 1 ] || die "usage: delphi setup [dir]"
  local dir=${1:-$HOME/.local/bin}
  mkdir -p "$dir" || die "cannot create $dir"
  printf '#!/bin/sh\nexec "%s/bin/delphi" "$@"\n' "$DELPHI_ROOT" > "$dir/delphi" && chmod +x "$dir/delphi" ||
    die "cannot write $dir/delphi"
  info "installed $dir/delphi"
  case ":$PATH:" in *":$dir:"*) ;; *) warn "$dir is not on PATH; add to your shell profile: export PATH=\"$dir:\$PATH\"" ;; esac
}
