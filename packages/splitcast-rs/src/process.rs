//! Linux process-group ownership without reaping the identity anchor early.
//!
//! Descendants must stay in the group. `setsid`/`setpgid` escape and controller
//! SIGKILL/crash cleanup require an enclosing cgroup with control-group killing.
//! For systemd services this means KillMode=control-group and SendSIGKILL=yes.
//! Drop is best effort, not a substitute for that service boundary. No process
//! API can promise bounded reaping of a task stuck in uninterruptible kernel I/O.
//! Callers must not independently reap these children or ignore SIGCHLD.

#[cfg(not(all(
    target_os = "linux",
    any(target_arch = "x86_64", target_arch = "aarch64")
)))]
compile_error!("process ownership currently supports Linux x86_64/aarch64 only");

use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Child, Command, ExitStatus, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

// Linux's siginfo_t union starts at the next pointer-aligned boundary.
#[repr(C)]
#[derive(Default)]
struct ChildInfo {
    pid: i32,
    uid: u32,
    status: i32,
    user_time: i64,
    system_time: i64,
}

#[repr(C)]
struct Siginfo {
    signo: i32,
    errno: i32,
    code: i32,
    data: ChildInfo,
    padding: [u8; 80],
}

unsafe extern "C" {
    fn kill(pid: i32, signal: i32) -> i32;
    fn waitid(kind: i32, id: u32, info: *mut Siginfo, options: i32) -> i32;
    fn fcntl(fd: i32, cmd: i32, ...) -> i32;
}

const TICK: Duration = Duration::from_millis(5);
const REAP_LIMIT: Duration = Duration::from_secs(1);

enum Ownership {
    Pinned,
    Reaped(ExitStatus),
}

pub struct OwnedProcess {
    child: Child,
    ownership: Ownership,
}

impl OwnedProcess {
    /// Executes argv directly in a fresh unprivileged process group.
    pub fn spawn(argv: &[String]) -> io::Result<Self> {
        let program = argv
            .first()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "empty argv"))?;
        let mut command = Command::new(program);
        command.args(&argv[1..]);
        command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        Self::spawn_command(&mut command)
    }

    fn spawn_command(command: &mut Command) -> io::Result<Self> {
        command.process_group(0);
        Ok(Self {
            child: command.spawn()?,
            ownership: Ownership::Pinned,
        })
    }

    pub fn id(&self) -> u32 {
        self.child.id()
    }

    /// Observes exit without reaping. Repeated observations preserve the group anchor.
    pub fn try_wait(&mut self) -> io::Result<Option<ExitStatus>> {
        if let Ownership::Reaped(status) = self.ownership {
            return Ok(Some(status));
        }
        let mut info = Siginfo {
            signo: 0,
            errno: 0,
            code: 0,
            data: ChildInfo::default(),
            padding: [0; 80],
        };
        // P_PID, WEXITED | WNOHANG | WNOWAIT. The child remains waitable.
        let rc = unsafe { waitid(1, self.id(), &mut info, 4 | 1 | 0x01000000) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        if info.data.pid == 0 {
            return Ok(None);
        }
        let raw = match info.code {
            1 => info.data.status << 8,
            2 => info.data.status,
            3 => info.data.status | 0x80,
            _ => return Err(io::Error::other("unexpected child exit notification")),
        };
        Ok(Some(ExitStatus::from_raw(raw)))
    }

    fn signal(&self, signal: i32) -> io::Result<()> {
        // Called only while the unreaped child pins this process-group number.
        if unsafe { kill(-(self.id() as i32), signal) } == 0 {
            return Ok(());
        }
        let error = io::Error::last_os_error();
        if error.raw_os_error() == Some(3) {
            Ok(())
        } else {
            Err(error)
        }
    }

    /// TERM, wait the full grace for descendants, KILL, then reap the leader.
    /// A kernel-stuck leader returns TimedOut after a further one second.
    pub fn stop(&mut self, grace: Duration) -> io::Result<ExitStatus> {
        if let Ownership::Reaped(status) = self.ownership {
            return Ok(status);
        }
        self.signal(15)?;
        thread::sleep(grace);
        self.signal(9)?;
        let start = Instant::now();
        loop {
            if self.try_wait()?.is_some() {
                let status = self.child.wait()?;
                self.ownership = Ownership::Reaped(status);
                return Ok(status);
            }
            if start.elapsed() >= REAP_LIMIT {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "owned leader did not exit after SIGKILL",
                ));
            }
            thread::sleep(TICK);
        }
    }
}

impl Drop for OwnedProcess {
    fn drop(&mut self) {
        if matches!(self.ownership, Ownership::Pinned) {
            let _ = self.stop(Duration::from_millis(50));
        }
    }
}

fn nonblocking(pipe: &impl AsRawFd) -> io::Result<()> {
    let fd = pipe.as_raw_fd();
    let flags = unsafe { fcntl(fd, 3) }; // F_GETFL
    if flags < 0 || unsafe { fcntl(fd, 4, flags | 0x800) } < 0 {
        // F_SETFL, O_NONBLOCK
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn drain(pipe: &mut impl Read, output: &mut Vec<u8>, remaining: &mut usize) -> io::Result<bool> {
    let mut buffer = [0; 8192];
    // One read per turn prevents a noisy pipe starving the other pipe or deadline.
    match pipe.read(&mut buffer) {
        Ok(0) => Ok(true),
        Ok(n) => {
            if n > *remaining {
                return Err(io::Error::other("helper output limit exceeded"));
            }
            output.extend_from_slice(&buffer[..n]);
            *remaining -= n;
            Ok(false)
        }
        Err(e)
            if matches!(
                e.kind(),
                io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
            ) =>
        {
            Ok(false)
        }
        Err(e) => Err(e),
    }
}

/// Runs a native helper without a shell. The cap covers stdout and stderr combined.
/// Timeout covers stdin, execution and pipe draining after spawn. Teardown adds
/// 50 ms TERM grace and up to one second to observe/reap the killed leader.
/// If teardown itself fails, Drop retries once (at most another 1.05 seconds).
/// Nonzero exit is returned in Output, not converted to an I/O error.
pub fn run_bounded(
    program: &str,
    args: &[String],
    input: Option<&[u8]>,
    timeout: Duration,
    output_cap: usize,
) -> io::Result<Output> {
    let start = Instant::now();
    let mut command = Command::new(program);
    command
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    command.stdin(if input.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    });
    let mut process = OwnedProcess::spawn_command(&mut command)?;
    let result = (|| {
        let mut stdout = process.child.stdout.take().unwrap();
        let mut stderr = process.child.stderr.take().unwrap();
        let mut stdin = process.child.stdin.take();
        nonblocking(&stdout)?;
        nonblocking(&stderr)?;
        if let Some(pipe) = &stdin {
            nonblocking(pipe)?;
        }
        let mut input = input.unwrap_or_default();
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let (mut out_done, mut err_done) = (false, false);
        let mut remaining = output_cap;
        loop {
            if start.elapsed() >= timeout {
                return Err(io::Error::new(io::ErrorKind::TimedOut, "helper timed out"));
            }
            if input.is_empty() {
                stdin.take();
            }
            if let Some(pipe) = &mut stdin {
                match pipe.write(&input[..input.len().min(8192)]) {
                    Ok(n) => input = &input[n..],
                    Err(e)
                        if matches!(
                            e.kind(),
                            io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                        ) =>
                    {
                        ()
                    }
                    Err(e) => return Err(e),
                }
            }
            if !out_done {
                out_done = drain(&mut stdout, &mut out, &mut remaining)?;
            }
            if !err_done {
                err_done = drain(&mut stderr, &mut err, &mut remaining)?;
            }
            if let Some(status) = process.try_wait()? {
                if out_done && err_done {
                    return Ok(Output {
                        status,
                        stdout: out,
                        stderr: err,
                    });
                }
            }
            thread::sleep(TICK);
        }
    })();
    let cleanup = process.stop(if result.is_ok() {
        Duration::ZERO
    } else {
        Duration::from_millis(50)
    });
    match result {
        Ok(output) => {
            cleanup?;
            Ok(output)
        }
        Err(error) => {
            cleanup?;
            Err(error)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT: AtomicUsize = AtomicUsize::new(0);

    struct Marker(PathBuf);

    impl Marker {
        fn new() -> Self {
            Self(std::env::temp_dir().join(format!(
                "splitcast-process-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            )))
        }

        fn pid(&self) -> u32 {
            let start = Instant::now();
            loop {
                if let Ok(text) = fs::read_to_string(&self.0) {
                    if let Ok(pid) = text.trim().parse() {
                        return pid;
                    }
                }
                assert!(
                    start.elapsed() < Duration::from_secs(3),
                    "child did not publish pid"
                );
                thread::sleep(TICK);
            }
        }
    }

    impl Drop for Marker {
        fn drop(&mut self) {
            let _ = fs::remove_file(&self.0);
        }
    }

    fn argv(script: String) -> Vec<String> {
        vec!["bash".into(), "-c".into(), script]
    }

    fn assert_terminated(pid: u32) {
        let start = Instant::now();
        loop {
            let stat = fs::read_to_string(format!("/proc/{pid}/stat"));
            match stat {
                Err(e) if e.kind() == io::ErrorKind::NotFound => return,
                Ok(stat)
                    if stat
                        .rsplit_once(')')
                        .unwrap()
                        .1
                        .trim_start()
                        .starts_with('Z') =>
                {
                    return
                }
                _ => (),
            }
            assert!(
                start.elapsed() < Duration::from_secs(2),
                "process {pid} survived teardown"
            );
            thread::sleep(TICK);
        }
    }

    fn orphan_script(marker: &Marker) -> String {
        format!("bash -c 'trap \"\" TERM; echo $$ > {}; while :; do sleep 1; done' &\nwhile [ ! -s {} ]; do sleep 0.01; done\nexit 23", marker.0.display(), marker.0.display())
    }

    #[test]
    fn early_leader_exit_still_cleans_term_ignoring_descendants() {
        let marker = Marker::new();
        let mut process = OwnedProcess::spawn(&argv(orphan_script(&marker))).unwrap();
        let descendant = marker.pid();
        let leader = process.id();
        let start = Instant::now();
        loop {
            if let Some(status) = process.try_wait().unwrap() {
                assert_eq!(status.code(), Some(23));
                break;
            }
            assert!(start.elapsed() < Duration::from_secs(3));
            thread::sleep(TICK);
        }
        assert_eq!(process.try_wait().unwrap().unwrap().code(), Some(23));
        assert_eq!(
            process.stop(Duration::from_millis(30)).unwrap().code(),
            Some(23)
        );
        assert_terminated(descendant);
        assert!(
            !std::path::Path::new(&format!("/proc/{leader}")).exists(),
            "leader was not reaped"
        );
        assert_eq!(process.stop(Duration::ZERO).unwrap().code(), Some(23));
    }

    #[test]
    fn drop_kills_descendants_after_observed_leader_exit() {
        let marker = Marker::new();
        let mut process = OwnedProcess::spawn(&argv(orphan_script(&marker))).unwrap();
        let descendant = marker.pid();
        while process.try_wait().unwrap().is_none() {
            thread::sleep(TICK);
        }
        drop(process);
        assert_terminated(descendant);
    }

    #[test]
    fn helper_timeout_kills_group_and_reaps_leader() {
        let leader = Marker::new();
        let descendant = Marker::new();
        let script = format!("echo $$ > {}; bash -c 'trap \"\" TERM; echo $$ > {}; while :; do sleep 1; done' & wait", leader.0.display(), descendant.0.display());
        let start = Instant::now();
        let error = run_bounded(
            "bash",
            &argv(script)[1..],
            None,
            Duration::from_millis(300),
            1024,
        )
        .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
        assert!(start.elapsed() < Duration::from_secs(2));
        assert_terminated(descendant.pid());
        assert!(!std::path::Path::new(&format!("/proc/{}", leader.pid())).exists());
    }

    #[test]
    fn helper_output_cap_cleans_up_and_reaps_leader() {
        let marker = Marker::new();
        let script = format!("echo $$ > {}; trap '' TERM; while :; do printf '0123456789'; printf 'abcdefghij' >&2; done", marker.0.display());
        let error = run_bounded(
            "bash",
            &argv(script)[1..],
            None,
            Duration::from_secs(2),
            100,
        )
        .unwrap_err();
        assert!(error.to_string().contains("output limit"));
        assert!(!std::path::Path::new(&format!("/proc/{}", marker.pid())).exists());
    }

    #[test]
    fn helper_drains_both_streams_and_writes_input_without_deadlock() {
        let input = vec![b'x'; 128 * 1024];
        let output = run_bounded(
            "bash",
            &["-c".into(), "printf warning >&2; cat; exit 7".into()],
            Some(&input),
            Duration::from_secs(5),
            input.len() + 7,
        )
        .unwrap();
        assert_eq!(output.stdout, input);
        assert_eq!(output.stderr, b"warning");
        assert_eq!(output.status.code(), Some(7));
    }

    #[test]
    fn blocked_stdin_is_bounded() {
        let input = vec![0; 1024 * 1024];
        let error = run_bounded(
            "bash",
            &["-c".into(), "sleep 30".into()],
            Some(&input),
            Duration::from_millis(50),
            100,
        )
        .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
    }

    #[test]
    fn helper_counts_stderr_toward_combined_output_cap() {
        let error = run_bounded(
            "bash",
            &["-c".into(), "printf '%0200d' 0 >&2".into()],
            None,
            Duration::from_secs(1),
            100,
        )
        .unwrap_err();
        assert!(error.to_string().contains("output limit"));
    }

    #[test]
    fn helper_early_exit_with_inherited_pipes_is_bounded_and_cleans_descendants() {
        let marker = Marker::new();
        let error = run_bounded(
            "bash",
            &argv(orphan_script(&marker))[1..],
            None,
            Duration::from_millis(200),
            100,
        )
        .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
        assert_terminated(marker.pid());
    }

    #[test]
    fn helper_broken_stdin_reaps_on_io_error() {
        let marker = Marker::new();
        let script = format!("echo $$ > {}; exec 0<&-; sleep 30", marker.0.display());
        let input = vec![0; 1024 * 1024];
        let error = run_bounded(
            "bash",
            &argv(script)[1..],
            Some(&input),
            Duration::from_secs(2),
            100,
        )
        .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::BrokenPipe);
        assert!(!std::path::Path::new(&format!("/proc/{}", marker.pid())).exists());
    }

    #[test]
    fn waitid_layout_matches_linux_abi() {
        assert_eq!(std::mem::size_of::<Siginfo>(), 128);
        assert_eq!(std::mem::offset_of!(Siginfo, data), 16);
        assert_eq!(std::mem::offset_of!(ChildInfo, status), 8);
    }
}
