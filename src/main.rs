//! Delphi CLI entry point: resolves the Delphi repo, then dispatches the command. Errors print as
//! `delphi: <msg>` (exit 1); merge conflicts exit 2.

mod check;
mod checkout;
mod core;
mod harness;
mod manage;
mod parse;
mod pr;
mod provenance;
mod setup;
mod sync;
mod workspace;

use crate::core::{Fail, OFFLINE, YES};
use std::sync::atomic::Ordering;

const USAGE: &str = "usage: delphi <command> [args]

  create <scope> <name> --from <workspace.yml>   new workspace folder (PR)
  list                                           workspaces on origin/main
  checkout <workspace> [--as <checkout>]         sparse clone of the folder on your branch
  open [<checkout>] [--shell]                    start the harness (or a shell) in the folder
  refresh [<checkout>]                           merge origin/main (exit 2 on conflicts)
  diff [<checkout>] [--upstream]                 your changes vs main (or main's since refresh)
  propose [<checkout>] [--dry-run]               refresh, sync, check, push, open/update the PR
  status                                         every local checkout
  mv <old> <new>                                 move a source or workspace path (PR)
  sync [--check] [--base <rev>]                  reconcile links in this Delphi checkout
  check                                          validate the repo
  setup [dir]                                    record this Delphi checkout for use anywhere

Commands that write to Delphi accept --model, --effort, --yes; checkout commands --offline.
The Delphi repo is $DELPHI_ROOT, else the checkout containing the current directory,
else the one recorded by `delphi setup`.
";

fn run(args: &[String]) -> anyhow::Result<()> {
    let cmd = args.first().map(String::as_str).unwrap_or("");
    let rest = args.get(1..).unwrap_or(&[]);
    let group: fn(&str, &[String]) -> anyhow::Result<()> = match cmd {
        "" | "-h" | "--help" | "help" => {
            print!("{USAGE}");
            return Ok(());
        }
        "setup" => return setup::main(rest),
        "create" | "list" | "mv" => manage::main,
        "checkout" | "open" | "refresh" | "diff" | "propose" | "status" => checkout::main,
        "sync" => |_, a| sync::main(a),
        "check" => |_, a| check::main(a),
        _ => die!("unknown command '{cmd}' (see: delphi help)"),
    };
    YES.store(std::env::var("DELPHI_YES").as_deref() == Ok("1"), Ordering::Relaxed);
    OFFLINE.store(std::env::var("DELPHI_OFFLINE").as_deref() == Ok("1"), Ordering::Relaxed);
    crate::core::resolve_root()?;
    group(cmd, rest)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match run(&args) {
        Ok(()) => 0,
        Err(e) => {
            if let Some(Fail(c, m)) = e.downcast_ref::<Fail>() {
                if !m.is_empty() {
                    eprintln!("{m}");
                }
                *c
            } else {
                eprintln!("delphi: {e:#}");
                1
            }
        }
    };
    crate::core::run_deferred();
    std::process::exit(code);
}
