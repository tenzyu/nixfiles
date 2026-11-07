//! Not a production daemon. The legacy Python agent stays in service.
use splitcast_rs_core::{Lifecycle, Role, Session};
use std::process::ExitCode;
fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("selfcheck") => {
            let mut session = Session::new(Role::Capture);
            if session.prepare().is_ok() && session.prepared().is_ok() &&
                session.stop().is_ok() && session.stopped().is_ok() &&
                session.state() == Lifecycle::Idle
            {
                println!("splitcast-rs-core: lifecycle selfcheck passed; no media processed");
                ExitCode::SUCCESS
            } else {
                eprintln!("splitcast-rs-core: selfcheck failed");
                ExitCode::FAILURE
            }
        }
        _ => {
            eprintln!("usage: splitcast-rs-core selfcheck");
            eprintln!("not an active agent; use existing Python SplitCast until parity gates pass");
            ExitCode::FAILURE
        }
    }
}
