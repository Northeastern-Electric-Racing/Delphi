//! Delphi CLI entry point: resolves the Delphi repo, then dispatches on the command group. Errors
//! print as `delphi: <msg>` (exit 1); refresh conflicts exit 2.

mod block;
mod check;
mod compile;
mod core;
mod harness;
mod layout;
mod parse;
mod pr;
mod provenance;
mod route;
mod setup;
mod workspace;

use crate::core::{Exit, Raw};
use std::sync::atomic::Ordering;

const USAGE: &str = "usage: delphi <command> [args]

  layout new <scope> <layout> --from <manifest>  create a layout (branch + PR)
  layout list                                    list layouts on origin/main

  workspace new <layout> [--as <ws>] [--ref <branch>]
  workspace open [<ws>] [--model m] [--effort e] [--shell]
  workspace refresh [<ws>] [--ref <branch>]
  workspace diff [<ws>] [--upstream]            your changes (or Delphi's, with --upstream)
  workspace propose [<ws>] [--dry-run]
  workspace status [--offline]                   (alias: ws)

  block mv <old> <new>                           move/rename a source

  check                                          validate the repo
  setup [dir]                                    record this Delphi checkout for use anywhere

Commands that write to Delphi accept --model, --effort, --yes.
The Delphi repo is $DELPHI_ROOT, else the checkout containing the current directory,
else the one recorded by `delphi setup`.
";

fn run(args: &[String]) -> anyhow::Result<()> {
    let group = args.first().map(String::as_str).unwrap_or("");
    let rest = args.get(1..).unwrap_or(&[]);
    match group {
        "" | "-h" | "--help" | "help" => {
            print!("{USAGE}");
            return Ok(());
        }
        "setup" => return setup::main(rest),
        "layout" | "workspace" | "ws" | "block" | "check" => {}
        _ => die!("unknown command '{group}' (see: delphi help)"),
    }
    crate::core::YES.store(std::env::var("DELPHI_YES").as_deref() == Ok("1"), Ordering::Relaxed);
    crate::core::OFFLINE.store(std::env::var("DELPHI_OFFLINE").as_deref() == Ok("1"), Ordering::Relaxed);
    crate::core::resolve_root()?;
    match group {
        "layout" => layout::main(rest),
        "block" => block::main(rest),
        "check" => check::main(rest),
        _ => workspace::main(rest),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match run(&args) {
        Ok(()) => 0,
        Err(e) => {
            if let Some(Exit(c)) = e.downcast_ref::<Exit>() {
                *c
            } else if let Some(Raw(m)) = e.downcast_ref::<Raw>() {
                eprintln!("{m}");
                1
            } else {
                eprintln!("delphi: {e:#}");
                1
            }
        }
    };
    crate::core::run_deferred();
    std::process::exit(code);
}
