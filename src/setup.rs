//! `delphi setup [dir]`: record the Delphi checkout (default: the one containing the current
//! directory, or DELPHI_ROOT) in `~/.config/delphi/root`, so the installed binary finds it from
//! workspaces and anywhere else. Replaces lib/setup.sh's PATH wrapper: `cargo install` puts the
//! binary on PATH.

use crate::core::{cwd, env_nonempty, have, is_delphi_repo, root_config_file};
use crate::{die, info, warn};
use anyhow::Result;
use std::fs;
use std::path::PathBuf;

pub fn main(args: &[String]) -> Result<()> {
    if args.len() > 1 {
        die!("usage: delphi setup [dir]");
    }
    let dir = match args.first() {
        Some(d) => PathBuf::from(d),
        None => match env_nonempty("DELPHI_ROOT") {
            Some(r) => PathBuf::from(r),
            None => match cwd().ancestors().find(|d| is_delphi_repo(d)) {
                Some(d) => d.to_path_buf(),
                None => die!("not inside a Delphi checkout; run 'delphi setup <dir>'"),
            },
        },
    };
    let dir = match fs::canonicalize(&dir) {
        Ok(d) if is_delphi_repo(&d) => d,
        _ => die!("not a Delphi checkout (needs delphi.conf and context/): {}", dir.display()),
    };
    let f = root_config_file();
    let written = f.parent().is_some_and(|p| fs::create_dir_all(p).is_ok())
        && fs::write(&f, format!("{}\n", dir.display())).is_ok();
    if !written {
        die!("cannot write {}", f.display());
    }
    info!("recorded Delphi checkout {} in {}", dir.display(), f.display());
    if !have("delphi") {
        warn!("delphi is not on PATH; install it with: cargo install --path {}", dir.display());
    }
    Ok(())
}
