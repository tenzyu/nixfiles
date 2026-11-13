//! Private state files, resolved through pinned directory descriptors.
use std::fs;
use std::io::{self, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};

const O_DIRECTORY: i32 = 0x10000;
const O_NOFOLLOW: i32 = 0x20000;

fn invalid(message: &str) -> io::Error { io::Error::other(message) }

pub fn private_directory(path: &Path) -> io::Result<fs::File> {
    let path = if path.is_absolute() { path.to_owned() } else { std::env::current_dir()?.join(path) };
    let mut current = fs::File::open("/")?;
    for component in path.components() {
        let name = match component {
            Component::RootDir | Component::CurDir => continue,
            Component::Normal(name) => name,
            _ => return Err(invalid("invalid state directory")),
        };
        let next = PathBuf::from(format!("/proc/self/fd/{}", current.as_raw_fd())).join(name);
        match fs::DirBuilder::new().mode(0o700).create(&next) {
            Ok(()) => {},
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {},
            Err(e) => return Err(e),
        }
        current = fs::OpenOptions::new().read(true).custom_flags(O_DIRECTORY | O_NOFOLLOW).open(next)?;
    }
    unsafe extern "C" { fn getuid() -> u32; }
    if current.metadata()?.uid() != unsafe { getuid() } {
        return Err(invalid("state directory must belong to this user"));
    }
    current.set_permissions(fs::Permissions::from_mode(0o700))?;
    Ok(current)
}

pub fn atomic_file(path: &Path, contents: &str) -> io::Result<()> {
    let directory = private_directory(path.parent().ok_or_else(|| invalid("invalid state path"))?)?;
    let anchored = PathBuf::from(format!("/proc/self/fd/{}", directory.as_raw_fd()));
    let target = anchored.join(path.file_name().ok_or_else(|| invalid("invalid state filename"))?);
    match fs::symlink_metadata(&target) {
        Ok(m) if !m.is_file() => return Err(invalid("state target must be a regular file")),
        Ok(_) => {},
        Err(e) if e.kind() == io::ErrorKind::NotFound => {},
        Err(e) => return Err(e),
    }
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| invalid("invalid system clock"))?.as_nanos();
    let part = anchored.join(format!(".splitcast-{}-{stamp}-{}.tmp", std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
    let mut file = fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&part)?;
    let result = (|| {
        file.write_all(contents.as_bytes())?;
        file.sync_all()?;
        fs::rename(&part, &target)?;
        directory.sync_all()
    })();
    if result.is_err() { let _ = fs::remove_file(&part); }
    result
}
