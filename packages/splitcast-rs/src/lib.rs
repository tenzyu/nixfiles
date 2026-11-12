//! Unprivileged replacement core. Not an active SplitCast media service.
//! The existing Python controller remains authoritative until parity gates pass.
pub mod config;
pub mod control;
pub mod media;
pub mod obs;
use std::fmt;
use std::io;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::thread;
use std::time::{Duration, Instant};

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

// Signal the whole process group, not just its original leader. Only groups
// created by OwnedProcess may be targeted. This is Linux/Unix-only by design.
unsafe extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}
const SIGTERM: i32 = 15;
const SIGKILL: i32 = 9;

fn signal_group(pgid: i32, sig: i32) -> io::Result<()> {
    let rc = unsafe { kill(-pgid, sig) };
    if rc == 0 { return Ok(()); }
    let err = io::Error::last_os_error();
    // ESRCH: no process in the process group remains.
    if err.raw_os_error() == Some(3) { Ok(()) } else { Err(err) }
}

pub struct OwnedProcess {
    child: Child,
    pgid: i32,
    finished: bool,
}

impl OwnedProcess {
    /// argv[0] is a fixed executable, with no shell interpolation.
    /// The new process group is not granted any elevated privileges.
    pub fn spawn(argv: &[String]) -> io::Result<Self> {
        let program = argv.first().filter(|s| !s.is_empty())
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "empty argv"))?;
        let mut cmd = Command::new(program);
        cmd.args(&argv[1..]);
        cmd.process_group(0);
        cmd.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
        let child = cmd.spawn()?;
        let pgid = i32::try_from(child.id())
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "pid overflow"))?;
        Ok(Self { child, pgid, finished: false })
    }

    pub fn id(&self) -> u32 { self.child.id() }

    pub fn try_wait(&mut self) -> io::Result<Option<ExitStatus>> {
        let status = self.child.try_wait()?;
        if status.is_some() { self.finished = true; }
        Ok(status)
    }

    /// Best-effort group cleanup. An exact descendant lifecycle guarantee
    /// needs a systemd/cgroup v2 scope, not an eventually recycled PGID.
    pub fn stop(&mut self, grace: Duration) -> io::Result<ExitStatus> {
        if self.finished { return self.child.wait(); }
        // This process is not yet reaped, so its PID cannot be reused.
        signal_group(self.pgid, SIGTERM)?;
        let deadline = Instant::now() + grace;
        while Instant::now() < deadline {
            if let Some(status) = self.child.try_wait()? {
                self.finished = true;
                // Do not signal PGID after reaping: another process may reuse it.
                return Ok(status);
            }
            thread::sleep(Duration::from_millis(20));
        }
        // Leader still reserved its identity; terminate the group then reap.
        signal_group(self.pgid, SIGKILL)?;
        let status = self.child.wait()?;
        self.finished = true;
        Ok(status)
    }
}

impl Drop for OwnedProcess {
    fn drop(&mut self) {
        if !self.finished {
            let _ = self.stop(Duration::from_millis(200));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
