//! Unprivileged replacement core. Not an active SplitCast media service.
//! The existing Python controller remains authoritative until parity gates pass.
pub mod config;
pub mod control;
pub mod media;
pub mod obs;
pub mod process;
pub use process::{run_bounded, OwnedProcess};
use std::fmt;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Role {
    Capture,
    Production,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Lifecycle {
    Idle,
    Preparing,
    Ready,
    Running,
    Degraded,
    Stopping,
    Failed,
}

#[derive(Debug, Eq, PartialEq)]
pub struct TransitionError {
    pub from: Lifecycle,
    pub event: &'static str,
}

impl fmt::Display for TransitionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "invalid lifecycle transition: {:?} via {}", self.from, self.event)
    }
}

impl std::error::Error for TransitionError {}

#[derive(Debug)]
pub struct Session {
    role: Role,
    state: Lifecycle,
    /// There is no implicit start/restart, especially not for a live broadcast.
    output: Option<Output>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Output {
    Recording,
    Twitch,
}

impl Session {
    pub fn new(role: Role) -> Self {
        Self { role, state: Lifecycle::Idle, output: None }
    }
    pub fn role(&self) -> Role { self.role }
    pub fn state(&self) -> Lifecycle { self.state }
    pub fn output(&self) -> Option<Output> { self.output }

    fn transition(&mut self, allowed: &[Lifecycle], to: Lifecycle, event: &'static str)
        -> Result<(), TransitionError>
    {
        if !allowed.contains(&self.state) {
            return Err(TransitionError { from: self.state, event });
        }
        self.state = to;
        Ok(())
    }

    pub fn prepare(&mut self) -> Result<(), TransitionError> {
        self.transition(&[Lifecycle::Idle], Lifecycle::Preparing, "prepare")
    }
    pub fn prepared(&mut self) -> Result<(), TransitionError> {
        self.transition(&[Lifecycle::Preparing], Lifecycle::Ready, "prepared")
    }
    pub fn start(&mut self, output: Output) -> Result<(), TransitionError> {
        self.transition(&[Lifecycle::Ready], Lifecycle::Running, "start")?;
        self.output = Some(output);
        Ok(())
    }
    pub fn degrade(&mut self) -> Result<(), TransitionError> {
        self.transition(&[Lifecycle::Ready, Lifecycle::Running], Lifecycle::Degraded, "degrade")
    }
    pub fn fail(&mut self) -> Result<(), TransitionError> {
        self.transition(&[Lifecycle::Preparing, Lifecycle::Ready, Lifecycle::Running,
            Lifecycle::Degraded], Lifecycle::Failed, "fail")
    }
    pub fn stop(&mut self) -> Result<(), TransitionError> {
        // Idempotent stop prevents duplicate teardown and preserves rollback.
        if matches!(self.state, Lifecycle::Idle | Lifecycle::Stopping) {
            return Ok(());
        }
        self.transition(&[Lifecycle::Preparing, Lifecycle::Ready, Lifecycle::Running,
            Lifecycle::Degraded, Lifecycle::Failed], Lifecycle::Stopping, "stop")
    }
    /// Call only after all owned subprocess groups, listeners and routes are gone.
    pub fn stopped(&mut self) -> Result<(), TransitionError> {
        self.transition(&[Lifecycle::Stopping], Lifecycle::Idle, "stopped")?;
        self.output = None;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io, time::Duration};

    #[test]
    fn lifecycle_requires_explicit_authorization() {
        let mut session = Session::new(Role::Capture);
        assert!(session.start(Output::Twitch).is_err());
        session.prepare().unwrap();
        assert!(session.start(Output::Recording).is_err());
        session.prepared().unwrap();
        session.start(Output::Recording).unwrap();
        assert_eq!(session.output(), Some(Output::Recording));
        assert!(session.start(Output::Twitch).is_err());
        session.degrade().unwrap();
        assert!(session.start(Output::Twitch).is_err());
        session.stop().unwrap();
        session.stopped().unwrap();
        session.stop().unwrap(); // idempotent on Idle
        assert_eq!(session.state(), Lifecycle::Idle);
        assert_eq!(session.output(), None);
    }

    #[test]
    fn stops_a_owned_subprocess_group() {
        let mut p = OwnedProcess::spawn(&["bash".to_string(), "-c".to_string(),
            "sleep 30 & wait".to_string()]).unwrap();
        assert!(p.id() > 0);
        let status = p.stop(Duration::from_millis(100)).unwrap();
        assert!(!status.success());
    }

    #[test]
    fn rejects_empty_command() {
        assert_eq!(OwnedProcess::spawn(&[]).err().unwrap().kind(), io::ErrorKind::InvalidInput);
    }
}
